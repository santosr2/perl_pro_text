package Sift::Query::Grammar;
use v5.36;
use Moo;
use Marpa::R2;
use namespace::autoclean;

has grammar => (
    is      => 'lazy',
    builder => '_build_grammar',
);

sub _build_grammar ($self) {
    return Marpa::R2::Scanless::G->new({
        source => \(<<'END_BNF')
:default ::= action => do_args
lexeme default = latm => 1

# Top-level query structure
Query           ::= WhereClause GroupClause AggClauses SortClause LimitClause
                                                    action => build_query

# WHERE clause (can be just an expression without WHERE keyword)
WhereClause     ::= KW_WHERE Expression             action => where_clause
                  | Expression                      action => where_clause_implicit

# Expression grammar with proper precedence
Expression      ::= OrExpr                          action => do_first

OrExpr          ::= OrExpr KW_OR AndExpr            action => or_expr
                  | AndExpr                         action => do_first

AndExpr         ::= AndExpr KW_AND NotExpr          action => and_expr
                  | NotExpr                         action => do_first

NotExpr         ::= KW_NOT NotExpr                  action => not_expr
                  | Primary                         action => do_first

Primary         ::= LPAREN Expression RPAREN        action => paren_expr
                  | Comparison                      action => do_first
                  | InExpr                          action => do_first

# Comparison expressions
Comparison      ::= Field Comparator Value          action => comparison

Comparator      ::= OP_EQ                           action => op_eq
                  | OP_NE                           action => op_ne
                  | OP_GE                           action => op_ge
                  | OP_LE                           action => op_le
                  | OP_GT                           action => op_gt
                  | OP_LT                           action => op_lt

# IN expression
InExpr          ::= Field KW_IN LBRACE ValueList RBRACE
                                                    action => in_expr

ValueList       ::= Value+ separator => COMMA       action => value_list

# GROUP BY clause (optional via nullable)
GroupClause     ::= KW_GROUP KW_BY FieldList        action => group_clause
GroupClause     ::= KW_GROUP FieldList              action => group_clause_short
GroupClause     ::=                                 action => do_none

FieldList       ::= Field+ separator => COMMA       action => field_list

# Aggregation clauses (optional via wrapper)
AggClauses      ::= AggClauseList                   action => do_first
AggClauses      ::=                                 action => do_none

AggClauseList   ::= AggClause+                      action => agg_clauses

AggClause       ::= KW_COUNT                        action => count_agg
                  | KW_AVG Field                    action => avg_agg
                  | KW_SUM Field                    action => sum_agg
                  | KW_MIN Field                    action => min_agg
                  | KW_MAX Field                    action => max_agg

# SORT clause (optional via nullable)
SortClause      ::= KW_SORT KW_BY Field SortDir     action => sort_clause
SortClause      ::= KW_SORT Field SortDir           action => sort_clause_short
SortClause      ::=                                 action => do_none

SortDir         ::= KW_ASC                          action => sort_asc
                  | KW_DESC                         action => sort_desc
SortDir         ::=                                 action => do_none

# LIMIT clause (optional via nullable)
LimitClause     ::= KW_LIMIT NUMBER                 action => limit_clause
LimitClause     ::=                                 action => do_none

# Values
Field           ::= IDENT                           action => field

Value           ::= STRING                          action => do_string
                  | NUMBER                          action => do_number

# ========== LEXEMES ==========

# Keywords (case insensitive)
:lexeme ~ KW_WHERE    priority => 1
KW_WHERE      ~ 'where':i
:lexeme ~ KW_AND      priority => 1
KW_AND        ~ 'and':i
:lexeme ~ KW_OR       priority => 1
KW_OR         ~ 'or':i
:lexeme ~ KW_NOT      priority => 1
KW_NOT        ~ 'not':i
:lexeme ~ KW_IN       priority => 1
KW_IN         ~ 'in':i
:lexeme ~ KW_GROUP    priority => 1
KW_GROUP      ~ 'group':i
:lexeme ~ KW_BY       priority => 1
KW_BY         ~ 'by':i
:lexeme ~ KW_COUNT    priority => 1
KW_COUNT      ~ 'count':i
:lexeme ~ KW_AVG      priority => 1
KW_AVG        ~ 'avg':i
:lexeme ~ KW_SUM      priority => 1
KW_SUM        ~ 'sum':i
:lexeme ~ KW_MIN      priority => 1
KW_MIN        ~ 'min':i
:lexeme ~ KW_MAX      priority => 1
KW_MAX        ~ 'max':i
:lexeme ~ KW_SORT     priority => 1
KW_SORT       ~ 'sort':i
:lexeme ~ KW_LIMIT    priority => 1
KW_LIMIT      ~ 'limit':i
:lexeme ~ KW_ASC      priority => 1
KW_ASC        ~ 'asc':i
:lexeme ~ KW_DESC     priority => 1
KW_DESC       ~ 'desc':i

# Operators - define longer ones first to ensure proper matching
OP_GE         ~ '>='
OP_LE         ~ '<='
OP_NE         ~ '!='
OP_EQ         ~ '=='
OP_GT         ~ '>'
OP_LT         ~ '<'

# Punctuation
LPAREN        ~ '('
RPAREN        ~ ')'
LBRACE        ~ '{'
RBRACE        ~ '}'
COMMA         ~ ','

# Identifiers
IDENT         ~ ident_first ident_rest
IDENT         ~ ident_first
ident_first   ~ [a-zA-Z_]
ident_rest    ~ [a-zA-Z0-9_]+

# Literals
STRING        ~ ["] dq_chars ["]
STRING        ~ ['] sq_chars [']
STRING        ~ ["] ["]
STRING        ~ ['] [']
dq_chars      ~ dq_char+
dq_char       ~ [^"]
sq_chars      ~ sq_char+
sq_char       ~ [^']

# Numbers
NUMBER        ~ int_num
NUMBER        ~ neg_int_num
NUMBER        ~ float_num
NUMBER        ~ neg_float_num
int_num       ~ digit_seq
neg_int_num   ~ [-] digit_seq
float_num     ~ digit_seq [.] digit_seq
neg_float_num ~ [-] digit_seq [.] digit_seq
digit_seq     ~ [0-9]+

# Whitespace
:discard      ~ ws
ws            ~ [\s]+

END_BNF
    });
}

1;

__END__

=head1 NAME

Sift::Query::Grammar - Marpa::R2 grammar for Sift query language

=head1 DESCRIPTION

Defines the BNF grammar for Sift's log query language using Marpa::R2.

=cut
