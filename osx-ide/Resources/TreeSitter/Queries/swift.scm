; Swift syntax highlighting queries for tree-sitter

; Keywords
[
  "associatedtype"
  "class"
  "deinit"
  "enum"
  "extension"
  "fileprivate"
  "func"
  "import"
  "init"
  "inout"
  "internal"
  "let"
  "open"
  "operator"
  "private"
  "protocol"
  "public"
  "rethrows"
  "static"
  "struct"
  "subscript"
  "typealias"
  "var"
  "break"
  "case"
  "continue"
  "default"
  "defer"
  "do"
  "else"
  "fallthrough"
  "for"
  "guard"
  "if"
  "in"
  "repeat"
  "return"
  "switch"
  "where"
  "while"
  "as"
  "catch"
  "throw"
  "throws"
  "try"
  "is"
  "nil"
  "self"
  "Self"
  "super"
  "true"
  "false"
  "any"
  "some"
  "actor"
  "async"
  "await"
  "yield"
] @keyword

; Types and type identifiers
(type_identifier) @type
(
  (user_type) @type
  (#match? @type "^[A-Z][a-zA-Z0-9_]*$")
)

; Built-in types
[
  "Int"
  "Int8"
  "Int16"
  "Int32"
  "Int64"
  "UInt"
  "UInt8"
  "UInt16"
  "UInt32"
  "UInt64"
  "Float"
  "Double"
  "Bool"
  "String"
  "Character"
  "Array"
  "Dictionary"
  "Set"
  "Optional"
  "Void"
  "Any"
  "AnyObject"
] @type.builtin

; Functions and methods
(function_declaration
  name: (identifier) @function
)

(method_declaration
  name: (simple_identifier) @function.method
)

; Parameters
(parameter
  name: (simple_identifier) @variable.parameter
  type: (type_annotation)? @type
)

; Variables and properties
(pattern
  (identifier) @variable
)

(property_declaration
  (pattern
    (identifier) @variable
  )
)

; Comments
(comment) @comment

; String literals
(line_string_literal) @string
(multi_line_string_literal) @string

; Number literals
(integer_literal) @number
(real_literal) @float

; Boolean literals
[
  (true)
  (false)
] @boolean

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
  "!="
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
  "..<"
] @operator

; Attributes
(attribute) @attribute
 "@" @attribute

; Preprocessor directives
[
  "#if"
  "#else"
  "#elseif"
  "#endif"
  "#available"
  "#selector"
  "#keyPath"
  "#fileLiteral"
  "#imageLiteral"
  "#colorLiteral"
] @preproc
