;; Capture exported functions, arrow functions, variables, classes, and method definitions

(class_declaration
  name: (identifier) @class)

(interface_declaration
  name: (identifier) @class)

(enum_declaration
  name: (identifier) @enum)

(enum_constant
  name: (identifier) @enum_item)

(class_body
  (field_declaration) @class_variable)

(class_body
  (constructor_declaration) @method)

(class_body
  (method_declaration) @method)

(interface_body
  (method_declaration) @method)
