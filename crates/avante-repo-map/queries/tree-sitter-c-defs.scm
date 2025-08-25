;; Capture extern functions, variables, public classes, and methods
(function_definition
  (storage_class_specifier) @extern
) @function
(struct_specifier) @struct
(struct_specifier
  body: (field_declaration_list
    (field_declaration
      declarator: (field_identifier))? @class_variable
  )
)
(declaration
  (storage_class_specifier) @extern
) @variable
