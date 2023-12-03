# TODO: Add indicator of whether the control's value is "lerping" between frames
#       (use yellow somehow?).

#===============================================================================
#
#===============================================================================
class UIControls::BaseControl < BitmapSprite
  attr_reader   :value
  attr_accessor :disabled

  TEXT_COLOR          = Color.black
  TEXT_SIZE           = 18           # Default is 22 if size isn't explicitly set
  HOVER_COLOR         = Color.cyan   # For clickable area when hovering over it
  CAPTURE_COLOR       = Color.pink   # For area you clicked in but aren't hovering over
  DISABLED_COLOR      = Color.gray
  DISABLED_COLOR_DARK = Color.new(128, 128, 128)

  def initialize(width, height, viewport)
    super(width, height, viewport)
    self.bitmap.font.color = TEXT_COLOR
    self.bitmap.font.size = TEXT_SIZE

    @disabled = false
    @hover_area = nil   # Is a symbol from the keys for @interactions if the mouse is hovering over that interaction
    @captured_area = nil   # Is a symbol from the keys for @interactions (or :none) if this control is clicked in
    clear_changed
    invalidate
  end

  def width
    return self.bitmap.width
  end

  def height
    return self.bitmap.height
  end

  def mouse_pos
    mouse_coords = Mouse.getMousePos
    return nil, nil if !mouse_coords
    ret_x = mouse_coords[0] - self.viewport.rect.x - self.x
    ret_y = mouse_coords[1] - self.viewport.rect.y - self.y
    return ret_x, ret_y
  end

  def set_interactive_rects
    @interactions = {}
  end

  def mouse_in_control?
    return false if !@interactions || @interactions.empty?
    mouse_x, mouse_y = mouse_pos
    return false if !mouse_x || !mouse_y
    @interactions.each_pair do |area, rect|
      return true if rect.contains?(mouse_x, mouse_y)
    end
    return false
  end

  #-----------------------------------------------------------------------------

  def disabled?
    return @disabled
  end

  def disable
    return if disabled?
    @disabled = true
    invalidate
  end

  def enable
    return if !disabled?
    @disabled = false
    invalidate
  end

  def invalid?
    return @invalid
  end

  # Marks that the control must be redrawn to reflect current logic.
  def invalidate
    @invalid = true
  end

  # Makes the control no longer invalid.
  def validate
    @invalid = false
  end

  def busy?
    return !@captured_area.nil?
  end

  def changed?
    return @changed
  end

  def set_changed
    @changed = true
  end

  def clear_changed
    @changed = false
  end

  #-----------------------------------------------------------------------------

  def draw_text(this_bitmap, text_x, text_y, this_text)
    text_size = this_bitmap.text_size(this_text)
    this_bitmap.draw_text(text_x, text_y, text_size.width, text_size.height, this_text, 0)
  end

  def draw_text_centered(this_bitmap, text_x, text_y, wid, this_text)
    text_size = this_bitmap.text_size(this_text)
    this_bitmap.draw_text(text_x, text_y, wid, text_size.height, this_text, 1)
  end

  # Redraws the control only if it is invalid.
  def repaint
    return if !invalid?
    refresh
    validate
  end

  def refresh
    # Paint over control to erase contents (intentionally not using self.bitmap.clear)
    self.bitmap.clear
    draw_area_highlight
  end

  def draw_area_highlight
    return if !@interactions || @interactions.empty?
    if !@captured_area || @hover_area == @captured_area
      # Draw mouse hover over area highlight
      rect = @interactions[@hover_area]
      self.bitmap.fill_rect(rect.x, rect.y, rect.width, rect.height, HOVER_COLOR) if rect
    elsif @captured_area
      # Draw captured area highlight
      rect = @interactions[@captured_area]
      self.bitmap.fill_rect(rect.x, rect.y, rect.width, rect.height, CAPTURE_COLOR) if rect
    end
  end

  #-----------------------------------------------------------------------------

  # This method is only called if the mouse is in the game window and this
  # control has interactive elements.
  def on_mouse_press
    return if !@interactions || @interactions.empty?
    return if @captured_area
    @captured_area = nil
    mouse_x, mouse_y = mouse_pos
    return if !mouse_x || !mouse_y
    @interactions.each_pair do |area, rect|
      next if !rect.contains?(mouse_x, mouse_y)
      @captured_area = area
      invalidate
      break
    end
  end

  def on_mouse_release
    @captured_area = nil
    invalidate
  end

  def update_hover_highlight
    # Remove the hover highlight if there are no interactions for this control
    # or if the mouse is off-screen
    mouse_x, mouse_y = mouse_pos
    if !@interactions || @interactions.empty? || !mouse_x || !mouse_y
      invalidate if @hover_area
      @hover_area = nil
      return
    end
    # Check each interactive area for whether the mouse is hovering over it, and
    # set @hover_area accordingly
    in_area = false
    @interactions.each_pair do |area, rect|
      next if !rect.contains?(mouse_x, mouse_y)
      invalidate if @hover_area != area
      @hover_area = area
      in_area = true
      break
    end
    if !in_area
      invalidate if @hover_area
      @hover_area = nil
    end
  end

  # Updates the logic on the control, invalidating it if necessary.
  def update
    return if !self.visible
    return if disabled? && !busy?

    update_hover_highlight

    # Detect a mouse press/release
    if @interactions && !@interactions.empty?
      if Input.trigger?(Input::MOUSELEFT)
        on_mouse_press
      elsif busy? && Input.release?(Input::MOUSELEFT)
        on_mouse_release
      end
    end

  end
end
