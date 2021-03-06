%{
  open Syntax
  open Unsigned

  let tuple_it es =
    match es with
      | [e] -> e
      | es -> ETuple es

  let tuple_pattern ps =
    match ps with
      | [p] -> p
      | ps -> PTuple ps

  let rec make_fun params body =
      match params with
	| [] -> body
	| (x,tyopt)::rest -> EFun {arg=x;argty=tyopt;resty=None;body=make_fun rest body;}
    
  let local_let (id,params) body =
    (id, make_fun params body)

  let merge_identifier = "merge"
  let trans_identifier = "trans"
  let init_identifier = "init"
    
  let global_let (id,params) body =
    let e = make_fun params body in
    if Var.name id = merge_identifier then
      DMerge e
    else if Var.name id = trans_identifier then
      DTrans e
    else if Var.name id = init_identifier then
      DInit e
    else
      DLet (id, make_fun params body)
%}

%token <Var.t> ID
%token <Unsigned.UInt32.t> NUM
%token AND OR NOT TRUE FALSE
%token PLUS SUB EQ LESS GREATER LEQ GEQ 
%token LET IN IF THEN ELSE FUN
%token SOME NONE MATCH WITH
%token DOT BAR ARROW SEMI LPAREN RPAREN LBRACKET RBRACKET LBRACE RBRACE COMMA UNDERSCORE EOF
%token STAR TOPTION TVECTOR ATTRIBUTE TYPE COLON TBOOL TINT
/* %token <Var.t> TID */
%token EDGES NODES

%start prog
%type  <Syntax.declarations> prog

%start expr
%type <Syntax.exp> expr

%left PLUS SUB      /* lowest precedence */
%left AND OR
%right NOT
%left DOT
%left LBRACKET      /* highest precedence */

%%
ty:
   | ty1 { $1 }
;

ty1:
   | ty2 { $1 }
   | ty2 ARROW ty1 { TArrow ($1, $3) }
;

ty2:
   | ty3 { $1 }
   | tuple { TTuple $1 }
;

tuple:
   | ty3 STAR ty3   { [$1;$3] }
   | ty3 STAR tuple { $1::$3 }
;

ty3:
   | ty4             { $1 }
   | ty3 TOPTION     { TOption $1 }
   | ty3 TVECTOR LBRACKET NUM RBRACKET {TMap ($4, $1)}
;

ty4:
   | TBOOL          { TBool }
   | TINT           { Syntax.tint }
   | LPAREN ty RPAREN { $2 }
/* | TID            { QVar $1 }       TO DO:  No user polymorphism for now */
;

param:
   | ID                         { ($1, None) }
   | LPAREN ID COLON ty RPAREN  { ($2, Some $4) }
;

params:
    | param            { [$1] }
    | param params     { $1::$2 }
;
  
letvars:
    | ID        { ($1,[]) }
    | ID params { ($1, $2) }
;

component:
    | LET letvars EQ expr               { global_let $2 $4 }
    | LET EDGES EQ LBRACE edges RBRACE  { DEdges $5 }
    | LET NODES EQ NUM                  { DNodes $4 }
    | TYPE ATTRIBUTE EQ ty              { DATy $4 }
;
  
components:
    | component                           { [$1] }
    | component components                { $1 :: $2 }
;

expr:
    | expr1                               { $1 }
;

expr1:
    | expr2                                               { $1 }
    | LET letvars EQ expr IN expr1                          { let (id, e) = local_let $2 $4 in ELet (id, e, $6) }
    | IF expr1 THEN expr ELSE expr1                       { EIf ($2, $4, $6) }
    | MATCH expr WITH branches                            { EMatch ($2, $4) }
    | FUN params ARROW expr1                              { make_fun $2 $4 }
;

expr2:
    | expr3                      { $1 }
    | expr2 expr3                { EApp ($1, $2) }
    | SOME expr3                 { ESome $2 }
;

expr3:
    | expr4                                        { $1 }
    | NOT expr3                                    { EOp (Not,[$2]) }
    | expr3 AND expr4                              { EOp (And, [$1;$3]) }
    | expr3 OR expr4                               { EOp (Or, [$1;$3]) }
    | expr3 PLUS expr4                             { EOp (UAdd, [$1;$3]) }
    | expr3 SUB expr4                              { EOp (USub, [$1;$3]) }
    | expr4 EQ expr4                               { EOp (UEq, [$1;$3]) }
    | expr4 LESS expr4                             { EOp (ULess, [$1;$3]) }
    | expr4 GREATER expr4                          { EOp (ULess, [$3;$1]) }
    | expr4 LEQ expr4                              { EOp (ULeq, [$1;$3]) }
    | expr4 GEQ expr4                              { EOp (ULeq, [$3;$1]) }
    | expr3 LBRACKET expr RBRACKET                 { EOp (MGet, [$1;$3]) }
    | expr3 LBRACKET expr EQ expr RBRACKET         { EOp (MSet, [$1;$3;$5]) }
    | expr3 DOT NUM                                { EProj (UInt32.to_int $3, $1) }
;

expr4:
    | ID                       { EVar $1 }
    | NUM                      { EVal (VUInt32 $1) }
    | TRUE                     { EVal (VBool true) }
    | FALSE                    { EVal (VBool false) }
    | NONE                     { EVal (VOption (None,None)) }
    | LPAREN exprs RPAREN      { tuple_it $2 }
    | LPAREN expr COLON ty RPAREN { ETy ($2, $4) }
;
	
exprs:
    | expr                     { [$1] }
    | expr COMMA exprs         { $1 :: $3 }
;

edge:
    | NUM SUB NUM SEMI         { [($1,$3)] }
    | NUM EQ NUM SEMI          { [($1,$3); ($3,$1)] }
;

edges:
    | edge                     { $1 }
    | edge edges               { $1 @ $2 }
;

pattern:
    | UNDERSCORE               { PWild }
    | ID                       { PVar $1 }
    | TRUE                     { PBool true }
    | FALSE                    { PBool false }
    | NUM                      { PUInt32 $1 }
    | LPAREN patterns RPAREN   { tuple_pattern $2 }
    | NONE                     { POption None }
    | SOME pattern             { POption (Some $2) }
;

patterns:
    | pattern                  { [$1] }
    | pattern COMMA patterns   { $1::$3 }
;

branch:
    | BAR pattern ARROW expr   { ($2, $4) }
;

branches:
    | branch                   { [$1] }
    | branch branches          { $1::$2 }
;

prog:
    | components EOF           { $1 }
;

/*
prog:
    | expr {$1 }
;
*/
