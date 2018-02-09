require "thor"
require "active_support" # for autoload
require "active_support/core_ext"

# Override thor's long_desc identation behavior
# https://github.com/erikhuda/thor/issues/398
class Thor
  module Shell
    class Basic
      def print_wrapped(message, options = {})
        message = "\n#{message}" unless message[0] == "\n"
        stdout.puts message
      end
    end
  end
end

module Skeleton
  class Command < Thor
    class << self
      # thor_args is an array of commands. Examples:
      #   ["help"]
      #   ["dynamodb:migrate"]
      #
      # Same signature as RakeCommand.perform.  Not using full_command.
      #
      # To call a thor task via ruby.
      # Signature is a little weird with the repetition, examples:
      #
      #   Skeleton::Main.perform("hello", ["hello"])
      #   Skeleton::Main.perform("dynamodb:migrate", ["migrate"])
      #
      def perform(full_command, thor_args)
        config = {} # doesnt seem like config is used
        dispatch(nil, thor_args, nil, config)
      end

      # Track all command subclasses.
      def subclasses
        @subclasses ||= []
      end

      def inherited(base)
        super

        if base.name
          self.subclasses << base
        end
      end

      # Useful for help menu when we need to have all the definitions loaded.
      # Using constantize instead of require so we dont care about
      # order. The eager load actually uses autoloading.
      def eager_load!
        path = File.expand_path("../../", __FILE__)
        Dir.glob("#{path}/**/*.rb").select do |path|
          next if !File.file?(path)

          class_name = path
                        .sub(/\.rb$/,'')
                        .sub(%r{.*/skeleton}, 'skeleton')
                        .classify

          # special mapping cases
          special_cases = {
            "Skeleton::Cli" => "Skeleton::CLI",
            "Skeleton::Version" => "Skeleton::VERSION",
          }
          class_name = special_cases[class_name] || class_name

          puts "eager_load! loading path: #{path} class_name: #{class_name}" if ENV['DEBUG']
          class_name.constantize # dont have to worry about order.
        end
      end

      # Fully qualifed task names. Examples:
      #   build
      #   process:controller
      #   dynamodb:migrate:down
      def namespaced_commands
        eager_load!
        subclasses.map do |klass|
          klass.all_tasks.keys.map do |task_name|
            klass = klass.to_s.sub('Skeleton::','')
            namespace = klass =~ /^Main/ ? nil : klass.underscore.gsub('/',':')
            [namespace, task_name].compact.join(':')
          end
        end.flatten.sort
      end

      # Use Skeleton banner instead of Thor to account for namespaces in commands.
      def banner(command, namespace = nil, subcommand = false)
        namespace = namespace_from_class(self)
        command_name = command.usage # set with desc when defining tht Thor class
        namespaced_command = [namespace, command_name].compact.join(':')

        "skeleton #{namespaced_command}"
      end

      def namespace_from_class(klass)
        namespace = klass.to_s.sub('Skeleton::', '').underscore.gsub('/',':')
        namespace unless namespace == "main"
      end

      def help_list(all=false)
        # hack to show hidden comands when requested
        Thor::HiddenCommand.class_eval do
          def hidden?; false; end
        end if all

        list = []
        eager_load!
        subclasses.each do |klass|
          commands = klass.printable_commands(true, false)
          commands.reject! { |array| array[0].include?(':help') }
          list += commands
        end

        list.sort_by! { |array| array[0] }
      end

      def klass_from_namespace(namespace)
        if namespace.nil?
          Skeleton::Main
        else
          class_name = namespace.gsub(':','/')
          class_name = "Skeleton::#{class_name.classify}"
          class_name.constantize
        end
      end

      # If this fails to match then it'l just return the original full command
      def autocomplete(full_command)
        return nil if full_command.nil? # skeleton help

        eager_load!

        words = full_command.split(':')
        namespace = words[0..-2].join(':') if words.size > 1
        command = words.last

        # Thor's normalize_command_name autocompletes the command but then we need to add the namespace back
        begin
          thor_subclass = klass_from_namespace(namespace) # could NameError
          command = thor_subclass.normalize_command_name(command) # could Thor::AmbiguousCommandError
          [namespace, command].compact.join(':')
        rescue NameError
          full_command # return original full_command
        rescue Thor::AmbiguousCommandError => e
          full_command # return original full_command
        end
      end
    end
  end
end