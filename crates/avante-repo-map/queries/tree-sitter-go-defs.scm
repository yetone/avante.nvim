;; Capture top-level functions and struct definitions
(var_declaration
  (var_spec) @variable
)
(const_declaration
  (const_spec) @variable
)
(function_declaration) @function
(type_declaration
  (type_spec (struct_type)) @class
)
(type_declaration
  (type_spec
    (struct_type
      (field_declaration_list
        (field_declaration) @class_variable)))
)
(method_declaration) @method
