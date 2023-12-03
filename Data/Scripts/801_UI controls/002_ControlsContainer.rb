#===============================================================================
# Controls are arranged in a list in self's bitmap. Each control is given an
# area of size "self's bitmap's width" x LINE_SPACING to draw itself in.
# TODO: The act of "capturing" a control makes other controls in this container
#       not update themselves, i.e. they won't colour themselves with a hover
#       highlight if the mouse happens to move over it while another control is
#       captured. Is there a better way of dealing with this? I'm leaning
#       towards the control itself deciding if it's captured, and it being
#       treated as uncaptured once it says its value has changed, but I think
#       this would require manually telling all other controls in this container
#       that something else is captured and they shouldn't show a hover
#       highlight when updated (perhaps as a parameter in def update), which I
#       don't think is ideal.
#===============================================================================
class UIControls::ControlsContainer
  attr_reader   :x, :y
  attr_accessor :label_offset_x, :label_offset_y
  attr_reader   :controls
  attr_reader   :values
  attr_reader   :visible
  attr_reader   :viewport

  LINE_SPACING        = 28
  OFFSET_FROM_LABEL_X = 90
  OFFSET_FROM_LABEL_Y = 0

  def initialize(x, y, width, height)
    @viewport = Viewport.new(x, y, width, height)
    @viewport.z = 99999
    @x = x
    @y = y
    @width = width
    @height = height
    @label_offset_x = OFFSET_FROM_LABEL_X
    @label_offset_y = OFFSET_FROM_LABEL_Y
    @controls = []
    @row_count = 0
    @pixel_offset = 0
    @captured = nil
    @visible = true
  end

  def dispose
    @controls.each { |c| c[1]&.dispose }
    @controls.clear
    @viewport.dispose
  end

  def busy?
    return !@captured.nil?
  end

  def changed?
    return !@values.nil?
  end

  def clear_changed
    @values = nil
  end

  def visible=(value)
    @visible = value
    @controls.each { |c| c[1].visible = value }
    repaint if @visible
  end

  def get_control(id)
    ret = nil
    @controls.each do |c|
      ret = c[1] if c[0] == id
      break if ret
    end
    return ret
  end

  #-----------------------------------------------------------------------------

  def add_label(id, label, has_label = false)
    id = (id.to_s + "_label").to_sym if !has_label
    add_control(id, UIControls::Label.new(*control_size(has_label), @viewport, label), has_label)
  end

  def add_labelled_label(id, label, text)
    add_label(id, label)
    add_label(id, text, true)
  end

  def add_header_label(id, label)
    ctrl = UIControls::Label.new(*control_size, @viewport, label)
    ctrl.header = true
    add_control(id, ctrl)
  end

  def add_checkbox(id, value, has_label = false)
    add_control(id, UIControls::Checkbox.new(*control_size(has_label), @viewport, value), has_label)
  end

  def add_labelled_checkbox(id, label, value)
    add_label(id, label)
    add_checkbox(id, value, true)
  end

  def add_text_box(id, value, has_label = false)
    add_control(id, UIControls::TextBox.new(*control_size(has_label), @viewport, value), has_label)
  end

  def add_labelled_text_box(id, label, value)
    add_label(id, label)
    add_text_box(id, value, true)
  end

  def add_number_slider(id, min_value, max_value, value, has_label = false)
    add_control(id, UIControls::NumberSlider.new(*control_size(has_label), @viewport, min_value, max_value, value), has_label)
  end

  def add_labelled_number_slider(id, label, min_value, max_value, value)
    add_label(id, label)
    add_number_slider(id, min_value, max_value, value, true)
  end

  def add_number_text_box(id, min_value, max_value, value, has_label = false)
    add_control(id, UIControls::NumberTextBox.new(*control_size(has_label), @viewport, min_value, max_value, value), has_label)
  end

  def add_labelled_number_text_box(id, label, min_value, max_value, value)
    add_label(id, label)
    add_number_text_box(id, min_value, max_value, value, true)
  end

  def add_button(id, button_text, has_label = false)
    add_control(id, UIControls::Button.new(*control_size(has_label), @viewport, button_text), has_label)
  end

  def add_labelled_button(id, label, button_text)
    add_label(id, label)
    add_button(id, button_text, true)
  end

  def add_list(id, rows, options, has_label = false)
    size = control_size(has_label)
    size[0] -= 8
    size[1] = rows * UIControls::List::ROW_HEIGHT
    add_control(id, UIControls::List.new(*size, @viewport, options), has_label, rows)
  end

  def add_labelled_list(id, label, rows, options)
    add_label(id, label)
    add_list(id, rows, options, true)
  end

  def add_dropdown_list(id, options, value, has_label = false)
    add_control(id, UIControls::DropdownList.new(*control_size(has_label), @viewport, options, value), has_label)
  end

  def add_labelled_dropdown_list(id, label, options, value)
    add_label(id, label)
    add_dropdown_list(id, options, value, true)
  end

  #-----------------------------------------------------------------------------

  def repaint
    @controls.each { |ctrl| ctrl[1].repaint }
  end

  def refresh; end

  #-----------------------------------------------------------------------------

  def update
    return if !@visible
    # Update controls
    if @captured
      # TODO: Ideally all controls will be updated here, if only to redraw
      #       themselves if they happen to be invalidated somehow. But that
      #       involves telling each control whether any other control is busy,
      #       to ensure that they don't show their hover colours or anything,
      #       which is fiddly and I'm not sure if it's the best approach.
      @captured.update
      @captured = nil if !@captured.busy?
    else
      @controls.each do |ctrl|
        ctrl[1].update
        @captured = ctrl[1] if ctrl[1].busy?
      end
    end
    # Check for updated controls
    @controls.each do |ctrl|
      next if !ctrl[1].changed?
      @values ||= {}
      @values[ctrl[0]] = ctrl[1].value
      ctrl[1].clear_changed
    end
    # Redraw controls if needed
    repaint
  end

  #-----------------------------------------------------------------------------

  def control_size(has_label = false)
    if has_label
      return @width - @label_offset_x, LINE_SPACING - @label_offset_y
    end
    return @width, LINE_SPACING
  end

  def add_control_at(id, control, x, y)
    control.x = x
    control.y = y
    control.set_interactive_rects
    @controls.push([id, control])
    repaint
  end

  def add_control(id, control, add_offset = false, rows = 1)
    i = @controls.length
    row_x = 0
    row_y = (add_offset ? @row_count - 1 : @row_count) * LINE_SPACING
    ctrl_x = row_x + (add_offset ? @label_offset_x : 0)
    ctrl_x += 4 if control.is_a?(UIControls::List)
    ctrl_y = row_y + (add_offset ? @label_offset_y : 0) + @pixel_offset
    add_control_at(id, control, ctrl_x, ctrl_y)
    @row_count += rows if !add_offset
    @pixel_offset -= (LINE_SPACING - UIControls::List::ROW_HEIGHT) * (rows - 1) if control.is_a?(UIControls::List)
  end
end
