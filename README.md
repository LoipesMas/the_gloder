# 🤖 The Gloder

Writing a decoder for your Gleam types can be a chore.

Why not let the machine do it for you?

Try it out: <https://loipesmas.github.io/the_gloder/>

(The Gloder is still in the alpha stage.)

---

The Gloder will convert your type definitions into a function that decodes a JSON string into that struct.
It handles all the basic types, optional fields, tuples and lists.

## Planned features

- [x] selecting decoder input (JSON, `Dynamic`, etc.)
- [x] selecting casing (kebab-case, snake_case, camelCase)
- [ ] generating encoders
- [ ] decoding enums/atoms
- [ ] decoding more than 9 fields
- [ ] *somehow* running in the editor
