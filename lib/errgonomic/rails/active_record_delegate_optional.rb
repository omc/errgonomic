# frozen_string_literal: true

module Errgonomic
  module Rails
    # Adds a `delegate_optional` class method in the spirit of Rails'
    # `delegate`, returning an Option instead of nil or NoMethodError when
    # the delegation target is absent.
    module ActiveRecordDelegateOptional
      extend ActiveSupport::Concern

      # What a declaration that cannot mean what it says is told, where it is
      # written. A writer is refused rather than delegated: an assignment
      # through an absent target has nowhere to put the value, and dropping it
      # silently is the failure an Option exists to prevent.
      NO_TARGET = "Delegation needs a target. Supply a keyword argument 'to' " \
                  '(e.g. delegate_optional :hello, to: :greeter).'
      NO_WRITERS = 'delegate_optional does not delegate a writer; an absent target would drop the value assigned'
      NO_NAME_TO_PREFIX = "prefix: true takes the target's own name, and a module target has none; name the prefix"
      NO_METHOD_TO_PREFIX = 'Can only automatically set the delegation prefix when delegating to a method.'
      ALWAYS_NONE = 'delegate_optional reads an absent target as None; allow_nil: false asks for something else'
      private_constant :NO_TARGET, :NO_WRITERS, :NO_NAME_TO_PREFIX, :NO_METHOD_TO_PREFIX, :ALWAYS_NONE

      # YARD does not see through a concern's class_methods block, so the
      # method it documents is declared rather than read.
      #
      # @!method delegate_optional(*methods, to: nil, prefix: nil, private: nil, allow_nil: nil)
      #   @example prefix forms name the reader, as they do for Rails' delegate
      #     article = Article.create!(title: 'Omelas', author: Author.create!(name: 'Ursula', bio: 'writes'))
      #     article.author_name # => Some('Ursula')
      #     article.writer_name # => Some('Ursula')
      #     article.bio # => Some('writes')
      #   @example a delegated call forwards what it was handed
      #     article = Article.create!(title: 'Omelas', author: Author.create!(name: 'Ursula'))
      #     article.author_greeting('Hello') # => Some('Hello, Ursula.')
      #     article.author_greeting('Hi', punctuation: '!') # => Some('Hi, Ursula!')
      #     article.author_styled_name(&:upcase) # => Some('URSULA')
      #   @example a target named for a Ruby keyword is reached through self
      #     Article.create!(title: 'Omelas').table_name # => Some('articles')
      #   @example the target is lifted, and an Option it hands back is not nested
      #     draft = Draft.create!(title: 'Omelas', author_id: Author.create!(name: 'Ursula').id)
      #     draft.author_name # => Some('Ursula')
      #     draft.byline_name # => Some('Ursula')
      #     Draft.create!(title: 'Untitled').author_name # => None()
      #     Article.create!(title: 'Untitled').author_name # => None()
      #   @example a delegated reader points at the model that declared it
      #     Article.instance_method(:author_name).source_location.first.end_with?('doctest_helper.rb') # => true
      #   @example an absent target is a value here, so allow_nil: true says nothing new
      #     Reprint.create!(title: 'Untitled').author_name # => None()
      #     Reprint.create!(title: 'Untitled').respond_to?(:bio) # => false
      #     begin
      #       Class.new(Reprint) { delegate_optional :name, to: :author, allow_nil: false }
      #     rescue ArgumentError => e
      #       e.message
      #     end # => 'delegate_optional reads an absent target as None; allow_nil: false asks for something else'
      #   @example a delegation needs a target
      #     begin
      #       Class.new(Reprint) { delegate_optional :name }
      #     rescue ArgumentError => e
      #       e.message
      #     end.start_with?("Delegation needs a target. Supply a keyword argument 'to'") # => true
      #   @example a writer is not delegated
      #     begin
      #       Class.new(Reprint) { delegate_optional :name=, to: :author }
      #     rescue ArgumentError => e
      #       e.message
      #     end # => 'delegate_optional does not delegate a writer; an absent target would drop the value assigned'
      #   @example a module target has no name to prefix with
      #     begin
      #       Class.new(Reprint) { delegate_optional :name, to: Errgonomic, prefix: true }
      #     rescue ArgumentError => e
      #       e.message
      #     end # => "prefix: true takes the target's own name, and a module target has none; name the prefix"
      #   @example an automatic prefix needs a target it can name a method after
      #     begin
      #       Class.new(Article) { delegate_optional :name, to: :@author, prefix: true }
      #     rescue ArgumentError => e
      #       e.message
      #     end # => 'Can only automatically set the delegation prefix when delegating to a method.'
      class_methods do
        # Names attributes that ActiveRecordOptional must leave alone. It has to
        # be callable before the include, which is what starts the wrapping for
        # a model that converts itself, so it lives here rather than in the
        # concern. Where the concern is included on a base class there is no
        # before, so it also takes back a reader already wrapped.
        def errgonomic_optional_except(*names)
          @errgonomic_optional_exceptions = errgonomic_optional_exceptions + names.map(&:to_s)
          errgonomic_unwrap_optionals(*names) if respond_to?(:errgonomic_unwrap_optionals)
          @errgonomic_optional_exceptions
        end

        def errgonomic_optional_exceptions
          @errgonomic_optional_exceptions ||=
            superclass.respond_to?(:errgonomic_optional_exceptions) ? superclass.errgonomic_optional_exceptions.dup : []
        end

        # How a None reaches a payload. :null writes it as null, which is
        # what Rails does with nil and what serde does with None unless a
        # field asks otherwise, so it is the default and needs no
        # declaration. :omit leaves the key out instead. only: and except:
        # scope the mode to named readers, and a reader outside the scope
        # keeps the default. Configuration reads as well above the include
        # as below it, so it lives here rather than in the concern.
        def errgonomic_serialize_none(mode, only: nil, except: nil)
          complaint = errgonomic_serialize_none_complaint(mode, only, except)
          raise ::ArgumentError, "errgonomic_serialize_none #{complaint}" if complaint

          @errgonomic_serialize_none = {
            mode: mode,
            only: only && Array(only).map(&:to_s),
            except: except && Array(except).map(&:to_s)
          }
        end

        # The nearest declaration is the whole story for a class: it replaces
        # whatever it inherits rather than layering onto it, so a scoped one
        # leaves every reader it does not name at the default.
        def errgonomic_serialize_none_declaration
          return @errgonomic_serialize_none if defined?(@errgonomic_serialize_none)
          return nil unless superclass.respond_to?(:errgonomic_serialize_none_declaration)

          superclass.errgonomic_serialize_none_declaration
        end

        # A declaration that cannot change what a payload looks like is a
        # mistake rather than a no-op, so say what to write instead. :null is
        # already what every unnamed reader gets, so scoping it names one set
        # of readers for the default and leaves the rest at the default too.
        def errgonomic_serialize_none_complaint(mode, only, except)
          return "takes :null or :omit, not #{mode.inspect}" unless %i[null omit].include?(mode)
          return 'takes only: or except:, not both; name the readers on one of them' if only && except
          return unless mode == :null && (only || except)

          ':null is the default for every reader and takes no only: or except:; ' \
            'declare :omit on the readers to leave out'
        end

        def delegate_optional(*methods, to: nil, prefix: nil, private: nil, allow_nil: nil)
          declared_at = caller_locations(1, 1).first
          complaint = delegate_optional_complaint(methods, to, prefix, allow_nil)
          raise ::ArgumentError, complaint if complaint

          receiver = delegate_optional_receiver(to)
          methods.each do |method_name|
            reader = "#{delegate_optional_prefix(to, prefix)}#{method_name}"
            define_optional_delegation(receiver, method_name, reader, declared_at)
            send(:private, reader) if private
          end
        end

        # Both ends lift exactly one layer, so a record, a nil and an Option
        # all delegate, and an Option the call returns is not wrapped twice.
        # The call is written out rather than sent, so the target's method is
        # reached on the same terms a caller would reach it on, and the reader
        # takes the declaration's file and line so a backtrace names the model.
        def define_optional_delegation(receiver, method_name, reader, declared_at)
          class_eval <<-RUBY, declared_at.path, declared_at.lineno # rubocop:disable Style/EvalWithLocation
            def #{reader}(...)
              #{receiver}.to_option.and_then { |target| target.#{method_name}(...).to_option }
            end
          RUBY
        end

        # A target named for a Ruby keyword reads as the keyword in the body
        # it is written into, so it needs an explicit receiver. Rails answers
        # the same question for delegate, and answers it for the same names.
        def delegate_optional_receiver(to)
          return to.to_s unless ::ActiveSupport::Delegation::RESERVED_METHOD_NAMES.include?(to.to_s)

          "self.#{to}"
        end

        # true asks for the target's own name; any other prefix is the name.
        def delegate_optional_prefix(to, prefix)
          return '' unless prefix

          "#{prefix == true ? to : prefix}_"
        end

        # A mistake is worth more where the declaration is written than as a
        # method nothing can call. allow_nil: true is what a delegation does
        # here anyway, so a swap from delegate carries; its opposite does not.
        def delegate_optional_complaint(methods, to, prefix, allow_nil)
          return NO_TARGET if to.nil?
          return NO_WRITERS if methods.any? { |method_name| /\A\w+=\z/.match?(method_name.to_s) }
          return ALWAYS_NONE if allow_nil == false

          delegate_optional_prefix_complaint(to, prefix)
        end

        # An automatic prefix is the target's own name, so the target needs
        # one, and one that can start a method name.
        def delegate_optional_prefix_complaint(to, prefix)
          return unless prefix == true
          return NO_NAME_TO_PREFIX if to.is_a?(::Module)

          NO_METHOD_TO_PREFIX if /^[^a-z_]/.match?(to.to_s)
        end
      end
    end
  end
end
