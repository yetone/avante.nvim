;; Capture functions, variables, nammespaces, classes, methods, and enums
(namespace_definition) @namespace
(function_definition) @function
(class_specifier) @class
(class_specifier
  body: (field_declaration_list
    (declaration
      declarator: (function_declarator))? @method
    (field_declaration
      declarator: (function_declarator))? @method
    (function_definition)? @method
    (function_declarator)? @method
    (field_declaration
      declarator: (field_identifier))? @class_variable
  )
)
(struct_specifier) @struct
(struct_specifier
  body: (field_declaration_list
    (declaration
      declarator: (function_declarator))? @method
    (field_declaration
      declarator: (function_declarator))? @method
    (function_definition)? @method
    (function_declarator)? @method
    (field_declaration
      declarator: (field_identifier))? @class_variable
  )
)
((declaration type: (_))) @variable
(enumerator_list ((enumerator) @enum_item))
