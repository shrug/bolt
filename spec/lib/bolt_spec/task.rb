require 'bolt_spec/files'

module BoltSpec
  module Task
    class TaskTypeMatcher
      def initialize(name, executable, input_method)
        @name = name
        @executable = Regexp.new(executable)
        @input_method = input_method
      end

      def ===(other)
        @name == other.name && @executable =~ other.executable && @input_method == other.input_method
      end

      def description
        "task_type(#{name}, #{executable}, #{input_method})"
      end
    end

    def mock_task(name, executable = nil, input_method = 'both')
      double('task', name: name, executable: executable || name, input_method: input_method)
    end

    def task_type(name, executable = nil, input_method = 'both')
      TaskTypeMatcher.new(name, executable || name, input_method)
    end

    include BoltSpec::Files
    def with_task_containing(name, contents, input_method, extension = nil)
      with_tempfile_containing(name, contents, extension) do |file|
        yield mock_task(name, file.path, input_method)
      end
    end
  end
end
