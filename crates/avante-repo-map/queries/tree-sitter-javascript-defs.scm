;; Capture exported functions, arrow functions, variables, classes, and method definitions
(export_statement
  declaration: (lexical_declaration
    (variable_declarator) @variable
  )
)
(export_statement
  declaration: (function_declaration) @function
)
(export_statement
  declaration: (class_declaration
    body: (class_body
      (field_definition) @class_variable
    )
  )
)
(export_statement
  declaration: (class_declaration
    body: (class_body
      (method_definition) @method
    )
  )
)
