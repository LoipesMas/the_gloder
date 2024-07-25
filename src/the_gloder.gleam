import blask/unstyled/select.{select}
import glance
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import justin
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event
import mat
import plinth/browser/clipboard
import sketch as s
import sketch/lustre as sketch_lustre
import sketch/options as sketch_options

type GloderError {
  GenerateError(String)
  ParseError(glance.Error)
}

type Case {
  KebabCase
  SnakeCase
  CamelCase
  PascalCase
}

fn case_to_str(case_: Case) {
  case case_ {
    KebabCase -> "kebab-case"
    SnakeCase -> "snake_case"
    CamelCase -> "camelCase"
    PascalCase -> "PascalCase"
  }
}

type Target {
  Dynamic
  JSON
}

fn target_to_str(target: Target) -> String {
  case target {
    Dynamic -> "dynamic"
    JSON -> "JSON"
  }
}

fn target_from_suffix(target: Target) -> String {
  case target {
    Dynamic -> "from_dynamic"
    JSON -> "from_json"
  }
}

type Settings {
  Settings(case_: Case, target: Target)
}

type Model {
  Model(
    input: String,
    casing_select_open: Bool,
    selected_case: Case,
    target_select_open: Bool,
    selected_target: Target,
  )
}

fn scl(styles) {
  styles |> s.class |> s.to_lustre
}

fn init(_flags) -> Model {
  Model(
    input: "User(name: String, age: Int)",
    casing_select_open: False,
    selected_case: KebabCase,
    target_select_open: False,
    selected_target: JSON,
  )
}

type Msg {
  ChangeText(String)
  UserClickedCopy
  ChangeCasingSelectOpen(Bool)
  CasingSelected(Case)
  ChangeTargetSelectOpen(Bool)
  TargetSelected(Target)
}

fn update(model: Model, msg: Msg) -> Model {
  let settings =
    Settings(case_: model.selected_case, target: model.selected_target)
  let output =
    parse(model.input)
    |> result.map_error(ParseError)
    |> result.try(generate(_, settings))
    |> result.map(string.replace(_, "\t", "  "))
    |> result.map_error(string.inspect)
    |> result.unwrap_both
  case msg {
    ChangeText(value) -> Model(..model, input: value)
    UserClickedCopy -> {
      clipboard.write_text(output)
      model
    }
    ChangeCasingSelectOpen(value) -> Model(..model, casing_select_open: value)
    CasingSelected(value) ->
      Model(..model, casing_select_open: False, selected_case: value)
    ChangeTargetSelectOpen(value) -> Model(..model, target_select_open: value)
    TargetSelected(value) ->
      Model(..model, target_select_open: False, selected_target: value)
  }
}

fn add_template(input) {
  "type YourData {" <> input <> "}"
}

fn parse(input: String) -> Result(glance.Module, glance.Error) {
  glance.module(add_template(input))
}

fn generate(
  input: glance.Module,
  settings: Settings,
) -> Result(String, GloderError) {
  use custom_type <- result.try(
    list.first(input.custom_types)
    |> result.replace_error(GenerateError("No custom types?")),
  )
  list.try_map(custom_type.definition.variants, fn(variant) {
    use decoder <- result.map(generate_decoder(variant, settings))
    let signature = generate_function_signature(variant, settings.target)
    let suffix = case settings.target {
      Dynamic -> "(value)"
      JSON -> "\n\t|> json.decode(from: json_string, using: _)"
    }
    mat.format3("{} {\n\t{}{}\n}", signature, decoder, suffix)
  })
  |> result.map(string.join(_, "\n\n"))
}

fn generate_function_signature(
  variant: glance.Variant,
  target: Target,
) -> String {
  case target {
    Dynamic ->
      mat.format2(
        "pub fn {}_from_dynamic(value: dynamic.Dynamic) -> Result({}, List(dynamic.DecodeError))",
        variant.name |> string.lowercase,
        variant.name,
      )
    JSON ->
      mat.format2(
        "pub fn {}_from_json(json_string: String) -> Result({}, json.DecodeError)",
        variant.name |> string.lowercase,
        variant.name,
      )
  }
}

fn generate_decoder(
  variant: glance.Variant,
  settings: Settings,
) -> Result(String, GloderError) {
  let field_count = list.length(variant.fields)
  use field_decoders <- result.map(
    list.try_map(variant.fields, generate_field_decode(_, settings)),
  )
  mat.format3(
    "dynamic.decode{}(\n\t\t{},\n\t\t{}\n\t)",
    field_count,
    variant.name,
    field_decoders |> string.join(",\n\t\t"),
  )
}

fn type_to_dynamic(
  type_: glance.Type,
  target: Target,
) -> Result(String, GloderError) {
  case type_ {
    glance.NamedType(name, parameters: parameters, ..) ->
      case name {
        "String" -> Ok("dynamic.string")
        "Int" -> Ok("dynamic.int")
        "Bool" -> Ok("dynamic.bool")
        "Float" -> Ok("dynamic.float")
        "List" ->
          list.first(parameters)
          |> result.replace_error(GenerateError("List requires a subtype"))
          |> result.try(type_to_dynamic(_, target))
          |> result.map(fn(type_) { mat.format1("dynamic.list({})", type_) })
        "Option" ->
          list.first(parameters)
          |> result.replace_error(GenerateError("Option requires a subtype"))
          |> result.try(type_to_dynamic(_, target))
          |> result.map(fn(type_) { mat.format1("dynamic.optional({})", type_) })
        n -> Ok(string.lowercase(n) <> "_" <> target_from_suffix(target))
      }
    glance.TupleType(types) ->
      case list.try_map(types, type_to_dynamic(_, target)) {
        Error(e) -> Error(e)
        Ok(types) ->
          Ok(mat.format2(
            "dynamic.decode{}({})",
            list.length(types),
            types |> string.join(", "),
          ))
      }
    glance.VariableType(..) ->
      Error(GenerateError("Variable types are not supported"))
    glance.FunctionType(..) ->
      Error(GenerateError("Function types are not supported"))
    glance.HoleType(..) -> Error(GenerateError("Hole types are not supported"))
  }
}

fn generate_field_decode(
  field: glance.Field(glance.Type),
  settings: Settings,
) -> Result(String, GloderError) {
  let case_converter = case settings.case_ {
    KebabCase -> justin.kebab_case
    SnakeCase -> justin.snake_case
    CamelCase -> justin.camel_case
    PascalCase -> justin.pascal_case
  }
  let res = case field.item {
    glance.NamedType("Option", parameters: parameters, ..) ->
      list.first(parameters)
      |> result.replace_error(GenerateError("Option requires a subtype"))
      |> result.try(type_to_dynamic(_, settings.target))
      |> result.map(fn(type_) { #("dynamic.optional_field", type_) })
    _ ->
      type_to_dynamic(field.item, settings.target)
      |> result.map(fn(type_) { #("dynamic.field", type_) })
  }
  use #(field_function, type_decoder) <- result.try(res)
  field.label
  |> option.to_result(GenerateError("Field needs a label"))
  |> result.map(case_converter)
  |> result.map(fn(label) {
    mat.format3("{}(\"{}\", {})", field_function, label, type_decoder)
  })
}

fn textarea_styles() {
  [
    s.property("tab-size", "2"),
    s.background("#111111"),
    s.border("none"),
    s.property("resize", "none"),
    s.padding_("10px"),
    s.margin_("0"),
  ]
}

fn input_class() {
  textarea_styles()
  |> list.append([
    s.color("whitesmoke"),
    s.background("#202020"),
    s.focus_visible([s.outline("none"), s.background("#222222")]),
    s.flex_grow("1"),
  ])
  |> scl
}

fn template_class() {
  textarea_styles()
  |> list.append([
    s.color("rgb(151, 151, 151)"),
    s.background("#151515"),
    s.focus_visible([s.outline("none"), s.background("#171717")]),
    s.flex_grow("0"),
    s.property("flex-shrink", "1"),
  ])
  |> scl
}

fn output_class() {
  textarea_styles()
  |> list.append([s.color("#77ff99"), s.flex_grow("2")])
  |> scl
}

fn text_holder_class() {
  [
    s.width_("90%"),
    s.height_("100%"),
    s.background("#000"),
    s.margin_("auto"),
    s.display("flex"),
    s.flex_direction("row"),
  ]
  |> scl
}

fn select_button_main_class() {
  [
    s.font_size_("1rem"),
    s.min_width_("220px"),
    s.padding_("0.6rem 0.8rem"),
    s.border_radius_("0"),
    s.border("none"),
    s.border_bottom("3px solid #485"),
    s.font_weight("600"),
    s.background("#bbb"),
    s.color("#111"),
    s.hover([
      s.cursor("pointer"),
      s.background("#eee"),
      s.border_bottom("3px solid #8f9"),
    ]),
  ]
  |> scl
}

fn select_button_list_class() {
  [
    s.font_size_("1rem"),
    s.padding_("0.6rem 0.8rem"),
    s.width_("100%"),
    s.border_radius_("0"),
    s.border("none"),
    s.border_bottom("3px solid #222"),
    s.font_weight("600"),
    s.background("#bbb"),
    s.color("#111"),
    s.hover([
      s.cursor("pointer"),
      s.background("#eee"),
      s.border_bottom("3px solid #8f9"),
    ]),
  ]
  |> scl
}

fn view(model: Model) -> element.Element(Msg) {
  let settings =
    Settings(case_: model.selected_case, target: model.selected_target)
  let output =
    parse(model.input)
    |> result.map_error(ParseError)
    |> result.try(generate(_, settings))
    |> result.map_error(string.inspect)
    |> result.unwrap_both
  html.div(
    [
      scl([
        s.display("flex"),
        s.flex_direction("column"),
        s.height_("100%"),
        s.font_family("monospace"),
      ]),
    ],
    [
      html.h1(
        [
          scl([
            s.text_align("center"),
            s.font_size_("2rem"),
            s.color("#44ff66"),
            s.margin_("0.5rem 0"),
          ]),
        ],
        [html.text("🤖 The Gloder")],
      ),
      html.div(
        [
          scl([
            s.width_("90%"),
            s.margin_("0.5rem auto"),
            s.display("flex"),
            s.flex_direction("row"),
            s.gap_("0.5rem"),
          ]),
        ],
        [
          html.div(
            [
              scl([
                s.margin_("auto 1.0rem auto 0"),
                s.color("whitesmoke"),
                s.font_size_("1.1rem"),
              ]),
            ],
            [html.text("Settings:")],
          ),
          select(
            open: model.casing_select_open,
            current: model.selected_case,
            options: [KebabCase, SnakeCase, CamelCase, PascalCase],
            on_toggle: ChangeCasingSelectOpen,
            on_select: CasingSelected,
            main_button: fn(option) {
              html.button([select_button_main_class()], [
                html.text("Case: " <> case_to_str(option)),
              ])
            },
            list_button: fn(option) {
              html.button([select_button_list_class()], [
                html.text(case_to_str(option)),
              ])
            },
            list_attrs: [scl([s.min_width_("220px")])],
          ),
          select(
            open: model.target_select_open,
            current: model.selected_target,
            options: [Dynamic, JSON],
            on_toggle: ChangeTargetSelectOpen,
            on_select: TargetSelected,
            main_button: fn(option) {
              html.button([select_button_main_class()], [
                html.text("Target: " <> target_to_str(option)),
              ])
            },
            list_button: fn(option) {
              html.button([select_button_list_class()], [
                html.text(target_to_str(option)),
              ])
            },
            list_attrs: [scl([s.min_width_("220px")])],
          ),
        ],
      ),
      html.div([text_holder_class()], [
        html.div(
          [
            scl([
              s.flex_grow("1"),
              s.display("flex"),
              s.flex_direction("column"),
              s.gap_("0"),
            ]),
          ],
          [
            html.textarea(
              [
                attribute.attribute("spellcheck", "false"),
                template_class(),
                attribute.disabled(True),
                attribute.rows(1),
              ],
              "type YourData {",
            ),
            html.textarea(
              [
                event.on_input(ChangeText),
                input_class(),
                attribute.attribute("spellcheck", "false"),
              ],
              model.input,
            ),
            html.textarea(
              [
                attribute.attribute("spellcheck", "false"),
                template_class(),
                attribute.disabled(True),
                attribute.rows(1),
              ],
              "}",
            ),
          ],
        ),
        html.div(
          [
            scl([
              s.flex_grow("2"),
              s.display("flex"),
              s.flex_direction("column"),
            ]),
          ],
          [
            html.textarea([output_class(), attribute.disabled(True)], output),
            html.button(
              [
                event.on_click(UserClickedCopy),
                scl([
                  s.position("absolute"),
                  s.bottom_("5vh"),
                  s.right_("10vw"),
                  s.font_size_("1.2rem"),
                  s.padding_("0.6rem 0.8rem"),
                  s.border_radius_("0"),
                  s.border("none"),
                  s.font_weight("600"),
                  s.background("#bbb"),
                  s.color("#111"),
                  s.hover([s.cursor("pointer"), s.background("#eee")]),
                ]),
              ],
              [html.text("📋 Copy")],
            ),
          ],
        ),
      ]),
    ],
  )
}

pub fn main() {
  let assert Ok(cache) =
    sketch_options.document()
    |> sketch_lustre.setup()

  let app =
    view
    |> sketch_lustre.compose(cache)
    |> lustre.simple(init, update, _)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}
