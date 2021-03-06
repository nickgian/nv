(* Interpreter for SRP attribute processing language *)
(* TO DO:  Use type environment to substitute types for type vars as we interpret *)

open Unsigned
open Syntax
open Printing
open Printf

(* Interpreter Errors *)

exception IError of string

let error s = raise (IError s)

(* Interpreter Environments *)

let empty_env = {ty= Env.empty; value= Env.empty}

let update_value env x v = {env with value= Env.update env.value x v}

let update_values env venv = {env with value= Env.updates env.value venv}

let update_ty env x t = {env with ty= Env.update env.ty x t}

let update_tys env tvs tys =
  let rec loop tenv tvs tys =
    match (tvs, tys) with
    | [], [] -> tenv
    | tv :: tvs, ty :: tys -> loop (Env.update tenv tv ty) tvs tys
    | _, _ -> error "wrong arity in type application"
  in
  {env with ty= loop env.ty tvs tys}


(* Equality of values *)

exception Equality of value

(* ignores type annotations when checking for equality *)
let rec equal_val v1 v2 =
  match (v1, v2) with
  | VBool b1, VBool b2 -> b1 = b2
  | VUInt32 i1, VUInt32 i2 -> UInt32.compare i1 i2 = 0
  | VMap (m1, _), VMap (m2, _) -> IMap.equal equal_val m1 m2
  | VTuple vs1, VTuple vs2 -> equal_vals vs1 vs2
  | VOption (None, _), VOption (None, _) -> true
  | VOption (Some v1, _), VOption (Some v2, _) -> equal_val v1 v2
  | VClosure _, _ -> raise (Equality v1)
  | _, VClosure _ -> raise (Equality v2)
  | VTyClosure _, _ -> raise (Equality v1)
  | _, VTyClosure _ -> raise (Equality v2)
  | _, _ -> false


and equal_vals vs1 vs2 =
  match (vs1, vs2) with
  | [], [] -> true
  | v1 :: rest1, v2 :: rest2 -> equal_val v1 v2 && equal_vals rest1 rest2
  | _, _ -> false


(* Expression and operator interpreters *)
(* matches p b is Some env if v matches p and None otherwise; assumes no repeated variables in pattern *)
let rec matches p v =
  match (p, v) with
  | PWild, v -> Some Env.empty
  | PVar x, v -> Some (Env.bind x v)
  | PBool true, VBool true -> Some Env.empty
  | PBool false, VBool false -> Some Env.empty
  | PUInt32 i1, VUInt32 i2 ->
      if UInt32.compare i1 i2 = 0 then Some Env.empty else None
  | PTuple ps, VTuple vs -> matches_list ps vs
  | POption None, VOption (None, _) -> Some Env.empty
  | POption Some p, VOption (Some v, _) -> matches p v
  | (PBool _ | PUInt32 _ | PTuple _ | POption _), _ -> None


and matches_list ps vs =
  match (ps, vs) with
  | [], [] -> Some Env.empty
  | p :: ps, v :: vs -> (
    match matches p v with
    | None -> None
    | Some env1 ->
      match matches_list ps vs with
      | None -> None
      | Some env2 -> Some (Env.updates env2 env1) )
  | _, _ -> None


let rec match_branches branches v =
  match branches with
  | [] -> None
  | (p, e) :: branches ->
    match matches p v with
    | Some env -> Some (env, e)
    | None -> match_branches branches v


let rec interp_exp env e =
  match e with
  | EVar x -> Env.lookup env.value x
  | EVal v -> v
  | EOp (op, es) -> interp_op env op es
  | EFun f -> VClosure (env, f)
  | ETyFun f -> VTyClosure (env, f)
  | EApp (e1, e2) -> (
      let v1 = interp_exp env e1 in
      let v2 = interp_exp env e2 in
      match v1 with
      | VClosure (c_env, f) -> interp_exp (update_value c_env f.arg v2) f.body
      | _ -> error "bad functional application" )
  | ETyApp (e1, tys) -> (
      let v1 = interp_exp env e1 in
      match v1 with
      | VTyClosure (c_env, (tvs, body)) ->
          interp_exp (update_tys c_env tvs tys) body
      | _ -> error "bad functional application" )
  | EIf (e1, e2, e3) -> (
    match interp_exp env e1 with
    | VBool true -> interp_exp env e2
    | VBool false -> interp_exp env e3
    | _ -> error "bad if condition" )
  | ELet (x, e1, e2) ->
      let v1 = interp_exp env e1 in
      interp_exp (update_value env x v1) e2
  | ETuple es -> VTuple (List.map (interp_exp env) es)
  | EProj (i, e) -> (
      if i < 0 then error (sprintf "negative projection from tuple: %d " i) ;
      match interp_exp env e with
      | VTuple vs ->
          if i >= List.length vs then
            error
              (sprintf "projection out of range: %d > %d" i (List.length vs)) ;
          List.nth vs i
      | _ -> error "bad projection" )
  | ESome e -> VOption (Some (interp_exp env e), None)
  | EMatch (e1, branches) ->
      let v = interp_exp env e1 in
      match match_branches branches v with
      | Some (env2, e) -> interp_exp (update_values env env2) e
      | None ->
          error
            ( "value " ^ value_to_string v
            ^ " did not match any pattern in match statement" )


and interp_op env op es =
  if arity op != List.length es then
    error
      (sprintf "operation %s has arity %d not arity %d" (op_to_string op)
         (arity op) (List.length es)) ;
  let vs = List.map (interp_exp env) es in
  match (op, vs) with
  | And, [(VBool b1); (VBool b2)] -> VBool (b1 && b2)
  | Or, [(VBool b1); (VBool b2)] -> VBool (b1 || b2)
  | Not, [(VBool b1)] -> VBool (not b1)
  | UAdd, [(VUInt32 i1); (VUInt32 i2)] -> VUInt32 (UInt32.add i1 i2)
  | UEq, [(VUInt32 i1); (VUInt32 i2)] ->
      if UInt32.compare i1 i2 = 0 then VBool true else VBool false
  | ULess, [(VUInt32 i1); (VUInt32 i2)] ->
      if UInt32.compare i1 i2 = -1 then VBool true else VBool false
  | MCreate t, [(VUInt32 i); v] -> VMap (IMap.create i v, t)
  | MGet, [(VMap (m, t)); (VUInt32 i)] -> (
    try IMap.find m i with IMap.Out_of_bounds i ->
      error ("bad get: " ^ UInt32.to_string i) )
  | MSet, [(VMap (m, t)); (VUInt32 i); v] -> VMap (IMap.update m i v, t)
  | MMap, [(VClosure (c_env, f)); (VMap (m, t))] ->
      VMap (IMap.map (fun v -> apply c_env f v) m, t)
  | MMerge, [(VClosure (c_env, f)); (VMap (m1, t1)); (VMap (m2, t2))] ->
      (* TO DO:  Need to preserve types in VOptions here ? *)
      let f_lifted v1opt v2opt =
        match
          apply c_env f (VTuple [VOption (v1opt, None); VOption (v2opt, None)])
        with
        | VOption (vopt, _) -> vopt
        | _ -> error "bad merge application; did not return option value"
      in
      VMap (IMap.merge f_lifted m1 m2, t1)
  | _, _ -> error "bad operator application"


and apply env f v = interp_exp (update_value env f.arg v) f.body

let interp e = interp_exp empty_env e

let interp_env env e = interp_exp env e

let interp_closure cl args = interp (Syntax.apply_closure cl args)
