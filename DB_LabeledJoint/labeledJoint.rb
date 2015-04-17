=begin
Creates a labeled dynamic component for the selected bounding box.
This code is an adaptation of Trimble's linetool.rb code.
=end

require 'sketchup.rb'
require 'DB_LabeledJoint/linetool.rb'


#------------------------------------------------------------------------------#
#
#                            Labeled Joint Module
#
#------------------------------------------------------------------------------#
module DB_LJ
class Labeled_Joint < LineTool
    # Takes two floats and (optional) epsilon. Returns boolean.
    def almost_equal(float1, float2, epsilon=0.000001)
        return (float1 - float2).abs < epsilon
    end
    
    # Takes Geom::Vector3d. Returns boolean.
    def is_zero_volume(v)
        return (almost_equal(v.x, 0.0) or 
                almost_equal(v.y, 0.0) or 
                almost_equal(v.z, 0.0))
    end
    
    # Takes two Geom::Point3d and a View.
    # Modifies model (and undo stack). Returns nothing.
    def create_geometry(pt1, pt2, view)
        model = view.model
        model.start_operation $exStrings.GetString("Labeled Joint")
        entities = model.entities
    
        # Verify selected region.
        if is_zero_volume(pt1.vector_to pt2)
            puts "Cannot create a zero-volume region"
            return
        end
        
        # Create a temporary layer for hiding / unhiding construction geometry.
        temp_hidden = model.layers.add "db_ TEMP HIDDEN"
        temp_hidden.visible = false
        start_layer = model.active_layer
        model.active_layer = temp_hidden
        
        # Make the box geometry.
        box = make_box(entities, pt1, pt2)
        exclude_id = box.entityID
        
        # Run user dialog for additional information and confirmation.
        Sketchup::set_status_text("Set joint parameters.", SB_PROMPT)
        results = set_dialog(model, exclude_id)
        if results == nil
            return
        end
        obj_name = results[0]
        
        # Set all object attributes.
        set_all_box_attributes(model, box, obj_name)
        
        # Determine configuration and add labels.
        ctr = box.bounds.center
#         puts ctr, ""
        geom_list = set_config(model, temp_hidden, ctr)
#         puts axes.to_s, ""
        model.active_layer = start_layer
        model.layers.remove(temp_hidden)
        apply_color(box, geom_list)
        
        model.commit_operation
    end # create_geometry()
    
    # Takes target model Entities and two Geom::Point3d. Returns a Group.
    def make_box(entities, pt1, pt2)
        # Get the base corners (pt1, pt_a, pt_b, pt_c). 
        pt_b = pt2.clone                # The point opposite pt1 on the base.
        pt_b.z = pt1.z                  # "Project" down to pt1's z-level.
        vec_a = Geom::Vector3d.new (pt1.vector_to pt_b).x, 0, 0
        pt_a = pt1 + vec_a              # A point between pt1 & pt_b.
        vec_c = Geom::Vector3d.new 0, (pt1.vector_to pt_b).y, 0
        pt_c = pt1 + vec_c              # The point opposite pt_a.
        # Make the base.
        base = entities.add_face(pt1, pt_a, pt_b, pt_c)
        # Get the height.
        vec = pt1.vector_to pt2
        height = vec.z
        if base.normal.z < 0        # Base normal pointing down
            height *= -1
        end
        # pushpull to make the box.
        base.pushpull(height)
        return entities.add_group(base.all_connected)
    end # make_box
    
    # Takes active model. Returns dialog results as an array.
    def set_dialog(model, exclude_id)
        obj_options = get_valid_groups(model, exclude_id)
        prompts =   ["New Object Name", "Parent Group"] #, "Height", "Flip Z?"]
        #TODO Preview of Z direction.
        defaults =  ["Joint", ""] #, 1, "False"]
        #TODO Increment default object name.
        options =   ["", (obj_options.keys.join "|")]
        results = UI.inputbox(prompts, defaults, options, "Set Joint Parameters")
        if results != false
            obj_name, group = results
            [obj_name, group]
            results
        else
            nil
        end #if
    end # set_dialog
    
    # Evaluates configuration of the joint by identifying the presence of 
    # adjacent geometry.
    def set_config(model, temp_layer, ctr)
        intersect_1 = box_raytest(model, ctr)
        temp_layer.visible = true
        intersect_2 = box_raytest(model, ctr)
        intersect_geom = []
        intersect_2.each_with_index do |g, i|
            if g != intersect_1[i] # @TODO replace with "almost equal"
                this_face = g.select {|e| e.typename == "Face"}
                intersect_geom << this_face[0]
            end
        end
        return intersect_geom
    end # set_config
    
    # Performs a raytest for all six principal directions.
    # Returns intersecting face/group info.
    def box_raytest(model, ctr)
        ##### @TODO Limit scope to selected group.
        p0 = model.raytest [ctr, [+1, 0, 0]]
        p1 = model.raytest [ctr, [-1, 0, 0]]
        p2 = model.raytest [ctr, [ 0,+1, 0]]
        p3 = model.raytest [ctr, [ 0,-1, 0]]
        p4 = model.raytest [ctr, [ 0, 0,+1]]
        p5 = model.raytest [ctr, [ 0, 0,-1]]
        return [p0[1], p1[1], p2[1], p3[1], p4[1], p5[1]]
    end # box_raytest
    
    # Takes the name hash set and the given group name. Returns a unique string.
    def get_unique_name(group_ids, name)
        # Correct for the empty string.
        default = "Group"
        if name.strip == ""
            name = default
        end
        # Include a counter for disambiguation.
        name = name + " (%d)"
        count = 1
        while group_ids.has_key?(name % count)
            count += 1
        end
        return name % count
    end # get_unique_name
    
    def get_valid_groups(model, exclude_id)
        entities = model.entities
        group_ids = Hash.new
        valid_groups = entities.select do |e| 
                e.valid? and
                e.typename == "Group" and 
                e.entityID != exclude_id
        end
        #TODO Do not show the group added by this tool.
        valid_groups.each do |e|
            this_name = get_unique_name(group_ids, e.name)
            group_ids[this_name] = e.entityID
        end
        return group_ids
    end
    
    def apply_color(group, geom_list)
        purple = [140,  50, 140]
        orange = [240, 140,  10]
        faces = group.entities.select {|e| e.typename == "Face"}        
        faces.each do |face| 
            if (geom_list.include? face)
                face.material = purple
                face.back_material = purple
                face.material.alpha = 0.4
            else
                face.material = orange
                face.back_material = orange
            end #if
        end   
    end
    
    def set_all_box_attributes(model, box, obj_name)
        b_box = box.local_bounds
        x_dim = b_box.width  # Along X
        y_dim = b_box.height # Along Y
        z_dim = b_box.depth  # Along Z
        box.name = obj_name
        box.description = "Labeled Joint"
#         puts box.name
        status = box.add_observer($dc_observers)
        if status == false
            puts "Warning: Adding $dc_observer not successful."
        end
        unit_string = get_unit_string(model)
        box.set_attribute("dynamic_attributes", "lenx", x_dim.to_inch)
        box.set_attribute("dynamic_attributes", "leny", y_dim.to_inch)
        box.set_attribute("dynamic_attributes", "lenz", z_dim.to_inch)
        box.set_attribute("dynamic_attributes", "_lenx_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_leny_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_lenz_access", "TEXTBOX")
        box.set_attribute("dynamic_attributes", "_lenx_units", unit_string)
        box.set_attribute("dynamic_attributes", "_leny_units", unit_string)
        box.set_attribute("dynamic_attributes", "_lenz_units", unit_string)
        dc_attr = box.attribute_dictionaries["dynamic_attributes"]
#         puts "Set attributes:"
#         dc_attr.each { |k, v| puts "\t" + k.to_s + " " + v.to_s }
        box.set_attribute("db_extrusion_object_attributes", "type", "extr")
        cust_attr = box.attribute_dictionaries["db_extrusion_object_attributes"]
#         puts "Set attributes:"
#         cust_attr.each { |k, v| puts "\t" + k.to_s + " " + v.to_s }
        dcs = $dc_observers.get_latest_class
        dcs.redraw_with_undo(box)
    end # set_all_box_attributes
    
    def get_unit_string(model)
        units_options = model.options["UnitsOptions"]
        length_format = units_options["LengthFormat"]
        length_units = units_options["LengthUnit"]
#         puts "Units", length_format, length_units
        if length_format == 0 and length_units == 1
            unit_string = "INCHES"
        elsif length_format == 0 and length_units == 2
            unit_string = "CM"
        elsif length_format == 0 and length_units == 3
            unit_string = "CM"
        elsif length_format == 0 and length_units == 4
            unit_string = "CM"
        elsif length_format == 2
            unit_string = "INCHES"
        else
            unit_string = "INCHES"
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
        return unit_string
    end # get_scale_factor

end # class Labeled_Joint
end # module DB_LJ
