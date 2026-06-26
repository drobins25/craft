; Vendored from:
; https://raw.githubusercontent.com/tree-sitter/tree-sitter-python/master/queries/tags.scm
; Pruned to the patterns this grammar version supports (4 kept, 0 dropped).
; Regenerate with: node tags/vendor-queries.mjs

(module (expression_statement (assignment left: (identifier) @name) @definition.constant))

(class_definition
  name: (identifier) @name) @definition.class

(function_definition
  name: (identifier) @name) @definition.function

(call
  function: [
      (identifier) @name
      (attribute
        attribute: (identifier) @name)
  ]) @reference.call
