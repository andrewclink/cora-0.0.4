require 'forwardable'
require 'fiber'

class Cora::Plugin

  # These could use some more work
  CONFIRM_REGEX = /yes|yeah|yep|ok|confirm|affirmative|indeed|engage/i
  DENY_REGEX = /no|nope|nah|cancel|negative/i

  extend Forwardable

  def_delegators :manager, :log, :location

  attr_accessor :manager, :match_data
  attr_reader :current_state

  class << self

    def listen_for(regex, options = {}, &block)
      listeners[regex] = {
        block: block,
        within_state: ([options[:within_state]].flatten)
      }
    end

    def listeners
      @listeners ||= {}
    end

  end

  def process(text)
    listeners.each do |regex, entry|
      if match = text.match(regex)
        captures = match.captures
        log "Matches #{regex}"

        if entry[:within_state]
          log 2, "Applicable states: #{entry[:within_state].join(', ')}"
          log current_state.nil? ? 2 : 1, "Current state: #{current_state}"

          if entry[:within_state].include?(current_state)
            log 3, "Matches, executing block"

            self.match_data = match
            Fiber.new {
              log 2, "Executing captures: #{captures.inspect}, entry: #{entry[:block].inspect}"
              result = instance_exec(*captures, &entry[:block])
            }.resume

            puts "-> Fiber complete"
            return true
          end
        end
      end

    end
    false
  end

  def listeners
    self.class.listeners
  end

  def say(text, options={})
    log "Say: #{text}"
    manager.respond(text, options)
  end

  def ask(question, options={})
    log "Ask: #{question}"
    
    f = Fiber.current
    options[:prompt_for_response] = true
    manager.respond(question, options)
    manager.set_callback do |text|
      f.resume(text)
    end

  end
  

  def confirm(question, options = {unmatched_message: "I'm sorry, I didn't understand that."}, &block)
    while (response = ask(question))
      if response.match(CONFIRM_REGEX)
        return true
      elsif response.match(DENY_REGEX)
        return false
      else
        say options[:unmatched_message]
      end
    end
  end

  def set_state(state)
    @current_state = state
    manager.set_priority_plugin(self)
  end

end
