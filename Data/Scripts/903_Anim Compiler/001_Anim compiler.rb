module Compiler
  module_function

  def compile_battle_animations(*paths)
    GameData::Animation::DATA.clear
    schema = GameData::Animation.schema
    sub_schema = GameData::Animation.sub_schema
    idx = 0
    # Read from PBS file(s)
    Console.echo_li(_INTL("Compiling animation PBS files..."))
    paths.each do |path|
      file_name = path.gsub(/^PBS\/Animations\//, "").gsub(/.txt$/, "")
      data_hash = nil
      current_particle = nil
      section_name = nil
      section_line = nil
      # Read each line of the animation PBS file at a time and compile it as an
      # animation property
      pbCompilerEachPreppedLine(path) do |line, line_no|
        echo "." if idx % 100 == 0
        idx += 1
        Graphics.update if idx % 500 == 0
        FileLineData.setSection(section_name, nil, section_line)
        if line[/^\s*\[\s*(.+)\s*\]\s*$/]
          # New section [anim_type, name]
          section_name = $~[1]
          section_line = line
          if data_hash
            validate_compiled_animation(data_hash)
            GameData::Animation.register(data_hash)
          end
          FileLineData.setSection(section_name, nil, section_line)
          # Construct data hash
          data_hash = {
            :pbs_path => file_name
          }
          data_hash[schema["SectionName"][0]] = get_csv_record(section_name.clone, schema["SectionName"])
          data_hash[schema["Particle"][0]] = []
          current_particle = nil
        elsif line[/^\s*<\s*(.+)\s*>\s*$/]
          # New subsection [particle_name]
          value = get_csv_record($~[1], schema["Particle"])
          current_particle = {
            :name => value
          }
          data_hash[schema["Particle"][0]].push(current_particle)
        elsif line[/^\s*(\w+)\s*=\s*(.*)$/]
          # XXX=YYY lines
          if !data_hash
            raise _INTL("Expected a section at the beginning of the file.\n{1}", FileLineData.linereport)
          end
          key = $~[1]
          if schema[key]   # Property of the animation
            value = get_csv_record($~[2], schema[key])
            if schema[key][1][0] == "^"
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] ||= []
              data_hash[schema[key][0]].push(value) if value
            else
              value = nil if value.is_a?(Array) && value.empty?
              data_hash[schema[key][0]] = value
            end
          elsif sub_schema[key]   # Property of a particle
            if !current_particle
              raise _INTL("Particle hasn't been defined yet!\n{1}", FileLineData.linereport)
            end
            value = get_csv_record($~[2], sub_schema[key])
            if sub_schema[key][1][0] == "^"
              value = nil if value.is_a?(Array) && value.empty?
              current_particle[sub_schema[key][0]] ||= []
              current_particle[sub_schema[key][0]].push(value) if value
            else
              value = nil if value.is_a?(Array) && value.empty?
              current_particle[sub_schema[key][0]] = value
            end
          end
        end
      end
      # Add last animation's data to records
      if data_hash
        FileLineData.setSection(section_name, nil, section_line)
        validate_compiled_animation(data_hash)
        GameData::Animation.register(data_hash)
      end
    end
    validate_all_compiled_animations
    process_pbs_file_message_end
    # Save all data
    GameData::Animation.save
  end

  def validate_compiled_animation(hash)
    # Split anim_type, move/common_name, version into their own values
    hash[:type] = hash[:id][0]
    hash[:move] = hash[:id][1]
    hash[:version] = hash[:id][2] || 0
    # Ensure there is no "Target" particle if "NoTarget" is set
    if hash[:particles].any? { |particle| particle[:name] == "Target" } && hash[:no_target]
      raise _INTL("Can't define a \"Target\" particle and also set property \"NoTarget\" to true.") + "\n" + FileLineData.linereport
    end
    # Create "User", "SE" and "Target" particles if they don't exist but should
    if hash[:particles].none? { |particle| particle[:name] == "User" }
      hash[:particles].push({:name => "User"})
    end
    if hash[:particles].none? { |particle| particle[:name] == "Target" } && !hash[:no_target]
      hash[:particles].push({:name => "Target"})
    end
    if hash[:particles].none? { |particle| particle[:name] == "SE" }
      hash[:particles].push({:name => "SE"})
    end
    # Go through each particle in turn
    hash[:particles].each do |particle|
      # Ensure the "Play"-type commands are exclusive to the "SE" particle, and
      # that the "SE" particle has no other commands
      if particle[:name] == "SE"
        particle.keys.each do |property|
          next if [:name, :se, :user_cry, :target_cry].include?(property)
          raise _INTL("Particle \"{1}\" has a command that isn't a \"Play\"-type command.",
             particle[:name]) + "\n" + FileLineData.linereport
        end
      else
        if particle[:se]
          raise _INTL("Particle \"{1}\" has a \"Play\" command but shouldn't.",
                      particle[:name]) + "\n" + FileLineData.linereport
        elsif particle[:user_cry]
          raise _INTL("Particle \"{1}\" has a \"PlayUserCry\" command but shouldn't.",
                      particle[:name]) + "\n" + FileLineData.linereport
        elsif particle[:target_cry]
          raise _INTL("Particle \"{1}\" has a \"PlayTargetCry\" command but shouldn't.",
                      particle[:name]) + "\n" + FileLineData.linereport
        end
      end
      # Ensure all particles have a default focus if not given
      if !particle[:focus] && particle[:name] != "SE"
        case particle[:name]
        when "User"   then particle[:focus] = :user
        when "Target" then particle[:focus] = :target
        else               particle[:focus] = :screen
        end
      end
      # Ensure user/target particles have a default graphic if not given
      if !particle[:graphic] && particle[:name] != "SE"
        case particle[:name]
        when "User"   then particle[:graphic] = "USER"
        when "Target" then particle[:graphic] = "TARGET"
        end
      end
      # Ensure that particles don't have a focus involving a target if the
      # animation itself doesn't involve a target
      if hash[:no_target] && [:target, :user_and_target].include?(particle[:focus])
        raise _INTL("Particle \"{1}\" can't have a \"Focus\" that involves a target if property \"NoTarget\" is set to true.",
          particle[:name]) + "\n" + FileLineData.linereport
      end
      # TODO: For SE particle, ensure that it doesn't play two instances of the
      #       same file in the same frame.
      # Convert all "SetXYZ" particle commands to "MoveXYZ" by giving them a
      # duration of 0 (even ones that can't have a "MoveXYZ" command)
      GameData::Animation::PARTICLE_KEYFRAME_DEFAULT_VALUES.keys.each do |prop|
        next if !particle[prop]
        particle[prop].each do |cmd|
          cmd.insert(1, 0) if cmd.length == 2 || particle[:name] == "SE"
          # Give default interpolation value of :linear to any "MoveXYZ" command
          # that doesn't have one already
          cmd.push(:linear) if cmd[1] > 0 && cmd.length < 4
        end
      end
      # Sort each particle's commands by their keyframe and duration
      particle.keys.each do |key|
        next if !particle[key].is_a?(Array)
        particle[key].sort! { |a, b| a[0] == b[0] ? a[1] == b[1] ? 0 : a[1] <=> b[1] : a[0] <=> b[0] }
        next if particle[:name] == "SE"
        # Check for any overlapping particle commands
        last_frame = -1
        last_set_frame = -1
        particle[key].each do |cmd|
          if last_frame > cmd[0]
            raise _INTL("Animation has overlapping commands for the {1} property.",
                        key.to_s.capitalize) + "\n" + FileLineData.linereport
          end
          if cmd[1] == 0 && last_set_frame >= cmd[0]
            raise _INTL("Animation has multiple \"Set\" commands in the same keyframe for the {1} property.",
                        key.to_s.capitalize) + "\n" + FileLineData.linereport
          end
          last_frame = cmd[0] + cmd[1]
          last_set_frame = cmd[0] if cmd[1] == 0
        end
      end
      # Ensure valid values for "SetBlending" commands
      if particle[:blending]
        particle[:blending].each do |blend|
          next if blend[2] <= 2
          raise _INTL("Invalid blend value: {1} (must be 0, 1 or 2).\n{2}",
                      blend[2], FileLineData.linereport)
        end
      end

    end
  end

  def validate_all_compiled_animations; end
end

#===============================================================================
# Hook into the regular Compiler to also compile animation PBS files.
#===============================================================================
module Compiler
  module_function

  def get_animation_pbs_files_to_compile
    ret = []
    if FileTest.directory?("PBS/Animations")
      Dir.all("PBS/Animations", "**/**.txt").each { |file| ret.push(file) }
    end
    return ret
  end

  class << self
    if !method_defined?(:__new_anims__get_all_pbs_files_to_compile)
      alias_method :__new_anims__get_all_pbs_files_to_compile, :get_all_pbs_files_to_compile
    end
    if !method_defined?(:__new_anims__compile_pbs_files)
      alias_method :__new_anims__compile_pbs_files, :compile_pbs_files
    end
  end

  def get_all_pbs_files_to_compile
    ret = __new_anims__get_all_pbs_files_to_compile
    extra = get_animation_pbs_files_to_compile
    ret[:Animation] = [nil, extra]
    return ret
  end

  def compile_pbs_files
    __new_anims__compile_pbs_files
    text_files = get_animation_pbs_files_to_compile
    compile_battle_animations(*text_files)
  end
end
