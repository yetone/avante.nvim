;; Capture top-level functions and struct definitions
(source_file
  (var_declaration
    (var_spec) @variable
  )
)
(source_file
  (const_declaration
    (const_spec) @variable
  )
)
(source_file
  (function_declaration) @function
)
(source_file
  (type_declaration
    (type_spec (struct_type)) @class
  )
)
(source_file
  (type_declaration
    (type_spec
      (struct_type
        (field_declaration_list
          (field_declaration) @class_variable)))
  )
)
(source_file
  (method_declaration) @method
)
