## Creates a labeled dynamic component for the selected bounding box.
## This code is an adaptation of Trimble's linetool.rb code.

require 'DB_LabeledJoint/labeledJoint.rb'

SKETCHUP_CONSOLE.show

UI.menu("Plugins").add_item("DB Labeled Joint") {
    Sketchup.active_model.select_tool(DB_LJ::Labeled_Joint.new)
}