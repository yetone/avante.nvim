;; Capture public functions, structs, methods, and variable definitions
(function_item) @function
(impl_item
  body: (declaration_list
    (function_item) @method
  )
)
(struct_item) @class
(struct_item
  body: (field_declaration_list
    (field_declaration) @class_variable
  )
)
(enum_item
  body: (enum_variant_list
    (enum_variant) @enum_item
  )
)
(const_item) @variable
(static_item) @variable
