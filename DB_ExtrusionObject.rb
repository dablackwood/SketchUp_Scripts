## First attempt to generate a dynamic component via Ruby extension.

require 'sketchup.rb'
require 'DB_ExtrusionObject/faceSelector.rb'

SKETCHUP_CONSOLE.show

UI.menu("Plugins").add_item("DB Extrusion Object") {
    Sketchup.active_model.select_tool(Face_Extruder.new)
}


#------------------------------------------------------------------------------#
#
#                            Face_Extruder Class
#
#------------------------------------------------------------------------------#
class Face_Extruder < Face_Selector
    
    def initialize
        puts "Face_Extruder initialized..."
        @face = nil
        @box = nil
        @obj = nil
        @point = nil
        @unit_string = "INCHES"
    end
    
    def activate
        puts "Face_Extruder activated"
        Sketchup::set_status_text("Select a face to extrude.", SB_PROMPT)
        @point = Sketchup::InputPoint.new
    end
    
    def set_dialog
        prompts =   ["New Object Name", "Height", "Flip Z?"]
        #TODO Preview of Z direction.
        defaults =  ["Extrusion", 1, "False"]
        #TODO Increment default object name.
        list =      ["", "", "False|True"]
        results = UI.inputbox(prompts, defaults, list, "Inputbox Example")
        puts results.class
        puts results
        if results != false
            obj_name, height, flip_z = results
            [obj_name, height, flip_z]
        else
            nil
        end #if
    end
    
    # Principal function executed after making selections.
    def optional_on_left_fn
        @face = get_face
        if @face.class != Sketchup::Face
            puts get_face.class
        else # Face object selected successfully.
            puts @face.class
            # Start dialog box.
            Sketchup::set_status_text("Set extrusion parameters.", SB_PROMPT)
            results = set_dialog
            if results == nil
                return
            end
            obj_name, height, flip_z = results
            @box = extrude_box(@face, obj_name, height, flip_z)
        end #if
    end # optional_on_left_fn
    
    # Absorbs the input face.
    def extrude_box(face, obj_name, height, flip_z)
        model = Sketchup.active_model
        status = model.start_operation("Extrusion Object", true)
        if status
            if flip_z
                face.reverse!
            end
            entities = model.entities
            # Correct for units.
            scale = get_scale_factor(model)
            face.pushpull(scale * height)
            box = entities.add_group(face.all_connected)
            b_box = box.local_bounds
            x_dim = b_box.width  # Along X
            y_dim = b_box.height # Along Y
            z_dim = b_box.depth  # Along Z
            box.name = obj_name
            box.description = "Extrusion Object"
            puts box.name
            set_all_box_attributes(box, x_dim, y_dim, z_dim)
            model.commit_operation
            box
        else
            return
        end #if
    end # extrude_box
    
    def get_scale_factor(model)
        units_options = model.options["UnitsOptions"]
        length_format = units_options["LengthFormat"]
        length_units = units_options["LengthUnit"]
        puts "Units", length_format, length_units
        scale = 1.0 # API operations are all in INCHES.
        if length_format == 0 and length_units == 1
            scale *= 12.0
            @unit_string = "INCHES"
        elsif length_format == 0 and length_units == 2
            scale /= 25.4
            @unit_string = "CM"
        elsif length_format == 0 and length_units == 3
            scale /= 2.54
            @unit_string = "CM"
        elsif length_format == 0 and length_units == 4
            scale /= 0.0254
            @unit_string = "CM"
        elsif length_format == 2
            scale *= 12.0
            @unit_string = "INCHES"
        else
            @unit_string = "INCHES"
        end
        # From SDK:
        # LengthFormat	0:	Decimal
 	    #               1:	Architectural
 	    #               2:	Engineering
 	    #               3:	Fractional
        # LengthUnit	0:	Inches
 	    #               1:	Feet
 	    #               2:	Millimeter
 	    #               3:	Centimeter
 	    #               4:	Meter
 	    # Note that LengthUnit will be overridden by LengthFormat if
 	    # LengthFormat is not set to Decimal. Architectural defaults to inches,
 	    # Engineering defaults to feet, and Fractional defaults to inches.
        return scale
    end # get_scale_factor
    
    def set_all_box_attributes(box, x_dim, y_dim, z_dim)
        status = box.add_observer($dc_observers)
        if status == false
            puts "Warning: Adding $dc_observer not successful."
        end
        box.set_attribute("dynamic_attributes", "lenx", x_dim.to_inch)
        box.set_attribute("dynamic_attributes", "leny", y_dim.to_inch)
        box.set_attribute("dynamic_attributes", "lenz", z_dim.to_inch)
        box.set_attribute("dynamic_attributes", "_lenx_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_leny_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_lenz_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_lenx_units", @unit_string)
        box.set_attribute("dynamic_attributes", "_leny_units", @unit_string)
        box.set_attribute("dynamic_attributes", "_lenz_units", @unit_string)
        dc_attr = box.attribute_dictionaries["dynamic_attributes"]
        puts "Set attributes:"
        dc_attr.each { |k, v| puts "\t" + k.to_s + " " + v.to_s }
        box.set_attribute("db_extrusion_object_attributes", "type", "extr")
        cust_attr = box.attribute_dictionaries["db_extrusion_object_attributes"]
        puts "Set attributes:"
        cust_attr.each { |k, v| puts "\t" + k.to_s + " " + v.to_s }
        dcs = $dc_observers.get_latest_class
        dcs.redraw_with_undo(box)
    end # set_all_box_attributes

end # class Face_Extruder