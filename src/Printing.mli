(* Printing utilities *)

open Syntax

val op_to_string : op -> string

val tyvar_to_string : tyvar -> string

val ty_to_string : ty -> string

val value_to_string : value -> string

val exp_to_string : exp -> string

val func_to_string : func -> string

val tyfunc_to_string : tyfunc -> string

val closure_to_string : closure -> string

val tyclosure_to_string : tyclosure -> string

val env_to_string : env -> string

val declaration_to_string : declaration -> string

val declarations_to_string : declarations -> string
