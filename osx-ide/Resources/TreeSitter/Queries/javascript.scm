; JavaScript syntax highlighting queries for tree-sitter

; Keywords
[
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "debugger"
  "default"
  "delete"
  "do"
  "else"
  "export"
  "extends"
  "finally"
  "for"
  "function"
  "if"
  "import"
  "in"
  "instanceof"
  "let"
  "new"
  "return"
  "super"
  "switch"
  "this"
  "throw"
  "try"
  "typeof"
  "var"
  "void"
  "while"
  "with"
  "yield"
  "async"
  "await"
] @keyword

; Types (TypeScript)
[
  "interface"
  "type"
  "implements"
  "namespace"
  "abstract"
  "public"
  "private"
  "protected"
  "readonly"
  "declare"
  "as"
  "is"
  "keyof"
  "unique"
  "unknown"
  "never"
] @keyword.type

; Functions and methods
(function_declaration
  name: (identifier) @function
)

(function_expression
  name: (identifier)? @function
)

(method_definition
  name: (property_identifier) @function.method
)

(arrow_function) @function

; Variables
(variable_declarator
  name: (identifier) @variable
)

(identifier) @variable

; Types
(type_identifier) @type
(predefined_type) @type.builtin

; Parameters
(formal_parameters
  (identifier) @variable.parameter
)

; Comments
(comment) @comment

; String literals
(string) @string
(template_string) @string

; Number literals
(number) @number

; Boolean literals
[
  "true"
  "false"
] @boolean

; Regular expressions
(regex) @string.special

; Punctuation
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "<"
  ">"
  "."
  ","
  ";"
  ":"
] @punctuation.delimiter

; Operators
[
  "="
  "+"
  "-"
  "*"
  "/"
  "%"
  "+="
  "-="
  "*="
  "/="
  "=="
  "==="
  "!="
  "!=="
  "<"
  "<="
  ">"
  ">="
  "&&"
  "||"
  "!"
  "&"
  "|"
  "^"
  "~"
  "<<"
  ">>"
  "??"
  "..."
] @operator

; Decorators
(decorator) @attribute
"@" @attribute

; Properties
(member_expression
  property: (property_identifier) @property
)

(shorthand_property_identifier) @property

; Labels
(statement_label) @label
