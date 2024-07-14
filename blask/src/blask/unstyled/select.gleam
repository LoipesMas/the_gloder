import gleam/list
import internals/utils.{scl}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import sketch as s

pub fn select(
  open open: Bool,
  current current_option: option_type,
  options options: List(option_type),
  on_toggle toggle_open: fn(Bool) -> a,
  on_select on_select: fn(option_type) -> a,
  main_button main_button: fn(option_type) -> Element(a),
  list_button list_button: fn(option_type) -> Element(a),
  list_attrs list_attrs: List(attribute.Attribute(a)),
) -> Element(a) {
  html.div(
    [],
    [
      html.div([event.on_click(toggle_open(!open)), scl([s.width_("100%")])], [
        main_button(current_option),
      ]
      ),
    ]
      |> list.append(case open {
        True -> [
          selection_list(
            options |> list.filter(fn(o) { o != current_option }),
            on_select,
            list_button,
            list_attrs,
          ),
        ]
        False -> []
      }),
  )
}

fn selection_list_class() {
  [s.display("flex"), s.flex_direction("column"), s.position("absolute")]
  |> scl
}

fn selection_list(
  options: List(option_type),
  on_select: fn(option_type) -> a,
  list_button: fn(option_type) -> Element(a),
  list_attrs: List(attribute.Attribute(a)),
) -> Element(a) {
  html.div(
    [selection_list_class()] |> list.append(list_attrs, _),
    list.map(options, fn(o) {
      html.div([event.on_click(on_select(o))], [list_button(o)])
    }),
  )
}
