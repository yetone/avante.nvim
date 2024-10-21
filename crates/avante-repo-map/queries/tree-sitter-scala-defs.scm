(class_definition
  name: (identifier) @class)

(object_definition
  name: (identifier) @class)

(trait_definition
  name: (identifier) @class)

(simple_enum_case
  name: (identifier) @enum_item)

(full_enum_case
  name: (identifier) @enum_item)

(template_body
  (function_definition) @method
)

(template_body
  (function_declaration) @method
)

(template_body
  (val_definition) @class_variable
)

(template_body
  (val_declaration) @class_variable
)


(template_body
  (var_definition) @class_variable
)

(template_body
  (var_declaration) @class_variable
)

(compilation_unit
  (function_definition) @function
)

(compilation_unit
  (val_definition) @variable
)

(compilation_unit
  (var_definition) @variable
)
