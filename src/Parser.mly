%{
  open Syntax
  open Unsigned

  let tuple_it es =
    match es with
      | [e] -> e
      | es -> ETuple es

  let rec make_fun params body =
      match params with
	| [] -> body
	| x::rest -> EFun (x, make_fun rest body)
    
  let local_let (id,params) body =
    (id, make_fun params body)

  let merge_identifier = "merge"
  let trans_identifier = "trans"
    
  let global_let (id,params) body =
    let e = make_fun params body in
    if Var.name id = merge_identifier then
      DMerge e
    else if Var.name id = trans_identifier then
      DTrans e
    else
      DLet (id, make_fun params body)
%}

%token <Var.t> ID
%token <Unsigned.UInt32.t> NUM
%token AND OR NOT TRUE FALSE
%token PLUS SUB EQ LESS GREATER LEQ GEQ 
%token LET IN IF THEN ELSE
%token SOME NONE MATCH WITH
%token DOT BAR ARROW SEMI LPAREN RPAREN LBRACKET RBRACKET LBRACE RBRACE COMMA EOF
%token EDGES NODES INIT

%start prog
%type <Syntax.declarations> prog

%left PLUS SUB      /* lowest precedence */
%left AND OR
%right NOT
%left DOT
%left LBRACKET      /* highest precedence */

%%

params:
    |               {[]}
    | ID params     {$1::$2}
;
  
fdecl:
    | ID params     {($1,$2)}
;

init:
    | NUM EQ expr SEMI {($1,$3)}
;

inits:
    |            { [] }
    | init inits { $1 :: $2 }
;

component:
    | LET fdecl EQ expr                 { global_let $2 $4 }
    | LET EDGES EQ RBRACE edges LBRACE  { DEdges $5 }
    | LET NODES EQ NUM                  { DNodes $4 }
    | LET INIT EQ RBRACE inits LBRACE   { DInit $5 }
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
    | LET fdecl EQ expr IN expr1                          { let (id, e) = local_let $2 $4 in ELet (id, e, $6) }
    | IF expr1 THEN expr ELSE expr1                       { EIf ($2, $4, $6) }
    | MATCH expr WITH NONE ARROW expr1 BAR ID ARROW expr1 { EMatch ($2, $6, $8, $10) }
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
    | NONE                     { EVal (VOption None) }
    | LPAREN exprs RPAREN      { tuple_it $2 }

	
exprs:
    | expr                     { [$1] }
    | expr COMMA exprs         { $1 :: $3 }
;

edge:
    | NUM SUB NUM              { [($1,$3)] }
    | NUM EQ NUM               { [($1,$3); ($3,$1)] }

edges:
    | edge                     { $1 }
    | edge SEMI edges          { $1 @ $3 }
;

prog:
    | components EOF           { $1 }
;

