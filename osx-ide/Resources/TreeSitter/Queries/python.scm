; Python syntax highlighting queries for tree-sitter

; Keywords
[
  "False"
  "None"
  "True"
  "and"
  "as"
  "assert"
  "async"
  "await"
  "break"
  "class"
  "continue"
  "def"
  "del"
  "elif"
  "else"
  "except"
  "finally"
  "for"
  "from"
  "global"
  "if"
  "import"
  "in"
  "is"
  "lambda"
  "nonlocal"
  "not"
  "or"
  "pass"
  "raise"
  "return"
  "try"
  "while"
  "with"
  "yield"
] @keyword

; Functions and methods
(function_definition
  name: (identifier) @function
)

(class_definition
  name: (identifier) @type
)

; Parameters
(parameters
  (identifier) @variable.parameter
)

(lambda_parameters
  (identifier) @variable.parameter
)

; Variables
(identifier) @variable

; Decorators
(decorator) @attribute
"@" @attribute

; Comments
(comment) @comment

; String literals
(string) @string

; Number literals
(integer) @number
(float) @float

; Boolean literals
[
  (true)
  (false)
] @boolean

; None
[
  (none)
] @constant.builtin

; Punctuation
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
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
  "//"
  "**"
  "+="
  "-="
  "*="
  "/="
  "//="
  "**="
  "=="
  "!="
  "<"
  "<="
  ">"
  ">="
  "and"
  "or"
  "not"
  "is"
  "in"
  "&"
  "|"
  "^"
  "~"
  "<<"
  ">>"
] @operator

; Built-in functions
(call
  function: (identifier) @function.builtin
  (#match? @function.builtin "^(abs|all|any|ascii|bin|bool|breakpoint|bytearray|bytes|callable|chr|classmethod|compile|complex|delattr|dict|dir|divmod|enumerate|eval|exec|filter|float|format|frozenset|getattr|globals|hasattr|hash|help|hex|id|input|int|isinstance|issubclass|iter|len|list|locals|map|max|memoryview|min|next|object|oct|open|ord|pow|print|property|range|repr|reversed|round|set|setattr|slice|sorted|staticmethod|str|sum|super|tuple|type|vars|zip)$")
)

; Built-in types
[
  "int"
  "float"
  "bool"
  "str"
  "bytes"
  "bytearray"
  "list"
  "tuple"
  "set"
  "frozenset"
  "dict"
  "type"
  "object"
] @type.builtin

; Import statements
(import_statement
  name: (dotted_name) @module
)

(import_from_statement
  module_name: (dotted_name) @module
)

; Exception handling
(try_statement
  "except" @keyword.exception
)

; Keywords in context
(while_statement
  "while" @keyword.repeat
)

(for_statement
  "for" @keyword.repeat
)

(if_statement
  "if" @keyword.conditional
  "elif" @keyword.conditional
  "else" @keyword.conditional
)
