require "pp"

RSpec.describe ValueSemantics do
  around do |example|
    # this is necessary for mutation testing to work properly
    with_constant(:Doggums, dog_class) { example.run }
  end

  let(:dog_class) do
    Class.new do
      include ValueSemantics.for_attributes {
        name
        trained?
      }
    end
  end

  describe 'initialization' do
    it "supports keyword arguments" do
      dog = Doggums.new(name: 'Fido', trained?: true)
      expect(dog).to have_attributes(name: 'Fido', trained?: true)
    end

    it "supports Hash arguments" do
      dog = Doggums.new({ name: 'Rufus', trained?: true })
      expect(dog).to have_attributes(name: 'Rufus', trained?: true)
    end

    it "supports any value that responds to #to_h" do
      arg = double(to_h: { name: 'Rex', trained?: true })
      dog = Doggums.new(arg)
      expect(dog).to have_attributes(name: 'Rex', trained?: true)
    end

    it "does not mutate hash arguments" do
      attrs = { name: 'Kipper', trained?: true }
      expect { Doggums.new(attrs) }.not_to change { attrs }
    end

    it "can not be constructed with attributes missing" do
      expect { dog = Doggums.new(name: 'Fido') }.to raise_error(
        ValueSemantics::MissingAttributes,
        "Attribute `Doggums#trained?` has no value",
      )
    end

    it "can not be constructed with undefined attributes" do
      expect {
        Doggums.new(name: 'Fido', trained?: true, meow: 'cattt', moo: 'cowww')
      }.to raise_error(
        ValueSemantics::UnrecognizedAttributes,
        "`Doggums` does not define attributes: `:meow`, `:moo`",
      )
    end

    it "can not be constructed with an object that does not respond to #to_h" do
      expect { dog_class.new(double) }.to raise_error(TypeError,
        <<~END_MESSAGE.strip.split.join(' ')
          Can not initialize a `Doggums` with a `RSpec::Mocks::Double` object.
          This argument is typically a `Hash` of attributes, but can be any
          object that responds to `#to_h`.
        END_MESSAGE
      )
    end

    it "does not intercept errors raised from calling #to_h" do
      arg = double
      allow(arg).to receive(:to_h).and_raise("this implementation sucks")

      expect { dog_class.new(arg) }.to raise_error("this implementation sucks")
    end
  end

  describe 'basic usage' do
    it "has attr readers and ivars" do
      dog = Doggums.new(name: 'Fido', trained?: true)

      expect(dog).to have_attributes(name: 'Fido', trained?: true)
      expect(dog.instance_variable_get(:@name)).to eq('Fido')
      expect(dog.instance_variable_get(:@trained)).to eq(true)
    end

    it "does not define attr writers" do
      dog = Doggums.new(name: 'Fido', trained?: true)

      expect{ dog.name = 'Goofy' }.to raise_error(NoMethodError, /name=/)
      expect{ dog.trained = false }.to raise_error(NoMethodError, /trained=/)
    end

    it "has square brackets as a variable attr reader" do
      dog = Doggums.new(name: 'Fido', trained?: true)

      expect(dog[:name]).to eq('Fido')
      expect { dog[:fins] }.to raise_error(
        ValueSemantics::UnrecognizedAttributes,
        "`Doggums` has no attribute named `:fins`"
      )
    end

    it "can do non-destructive updates" do
      sally = Doggums.new(name: 'Sally', trained?: false)
      bob = sally.with(name: 'Bob')

      expect(bob).to have_attributes(name: 'Bob', trained?: false)
    end

    it "can be converted to a hash of attributes" do
      dog = Doggums.new(name: 'Fido', trained?: false)

      expect(dog.to_h).to eq({ name: 'Fido', trained?: false })
    end

    it "has a human-friendly #inspect string" do
      dog = Doggums.new(name: 'Fido', trained?: true)
      expect(dog.inspect).to eq('#<Doggums name="Fido" trained?=true>')
    end

    it "has nice pp output" do
      output = StringIO.new

      dog = Doggums.new(name: "Fido", trained?: true)
      PP.pp(dog, output, 3)

      expect(output.string).to eq(<<~END_PP)
        #<Doggums
         name="Fido"
         trained?=true>
      END_PP
    end

    it "has a human-friendly module name" do
      mod = Doggums.ancestors[1]
      expect(mod.name).to eq("Doggums::ValueSemantics_Attributes")
    end

    it "has a frozen recipe" do
      vs = Doggums.value_semantics
      expect(vs).to be_a(ValueSemantics::Recipe)
      expect(vs).to be_frozen
      expect(vs.attributes).to be_frozen
      expect(vs.attributes.first).to be_frozen
    end
  end

  describe 'default values' do
    let(:cat) do
      Class.new do
        include ValueSemantics.for_attributes {
          name default: 'Kitty'
          scratch_proc default: ->{ "scratch" }
          born_at default_generator: ->{ Time.now }
        }
      end
    end

    it "uses the default if no value is given" do
      expect(cat.new.name).to eq('Kitty')
    end

    it "allows the default to be overriden" do
      expect(cat.new(name: 'Tomcat').name).to eq('Tomcat')
    end

    it "does not override nil" do
      expect(cat.new(name: nil).name).to be_nil
    end

    it "allows procs as default values" do
      expect(cat.new.scratch_proc.call).to eq("scratch")
    end

    it "can generate defaults with a proc" do
      expect(cat.new.born_at).to be_a(Time)
    end

    it "does not allow both `default:` and `default_generator:` options" do
      expect do
        ValueSemantics.for_attributes {
          both default: 5, default_generator: ->{ rand }
        }
      end.to raise_error(
        ArgumentError,
        "Attribute `both` can not have both a `:default` and a `:default_generator`",
      )
    end
  end

  describe 'validation' do
    module WingValidator
      def self.===(value)
        /feathery/.match(value)
      end
    end

    class Birb
      include ValueSemantics.for_attributes {
        wings WingValidator
      }
    end

    it "accepts values that pass the validator" do
      expect{ Birb.new(wings: 'feathery flappers') }.not_to raise_error
    end

    it "rejects values that fail the validator" do
      expect{ Birb.new(wings: 'smooth feet') }.to raise_error(
        ValueSemantics::InvalidValue,
        'Attribute `Birb#wings` is invalid: "smooth feet"',
      )
    end
  end

  describe "equality" do
    let(:puppy_class) { Class.new(Doggums) }

    let(:dog1) { Doggums.new(name: 'Fido', trained?: true) }
    let(:dog2) { Doggums.new(name: 'Fido', trained?: true) }
    let(:different) { Doggums.new(name: 'Brutus', trained?: false) }
    let(:child) { puppy_class.new(name: 'Fido', trained?: true) }

    it "defines loose equality between subclasses with #===" do
      expect(dog1).to eq(dog2)
      expect(dog1).not_to eq(different)
      expect(dog1).not_to eq("hello")

      expect(dog1).to eq(child)
      expect(child).to eq(dog1)
    end

    it "defines strict equality with #eql?" do
      expect(dog1.eql?(dog2)).to be(true)
      expect(dog1.eql?(different)).to be(false)

      expect(dog1.eql?(child)).to be(false)
      expect(child.eql?(dog1)).to be(false)
    end

    it "allows objects to be used as keys in Hash objects" do
      expect(dog1.hash).to eq(dog2.hash)
      expect(dog1.hash).not_to eq(different.hash)

      hash_key_test = { dog1 => 'woof', different => 'diff' }.merge(dog2 => 'bark')
      expect(hash_key_test).to eq({ dog1 => 'bark', different => 'diff' })
    end

    it "hashes differently depending on class" do
      expect(dog1.hash).not_to eq(child.hash)
    end
  end

  describe 'coercion' do
    module Callable
      def self.call(x)
        "callable: #{x}"
      end
    end

    class CoercionTest
      include ValueSemantics.for_attributes {
        no_coercion String, default: ""
        with_true String, coerce: true, default: ""
        with_callable String, coerce: Callable, default: ""
        double_it String, coerce: ->(x) { x * 2 }, default: "42"
      }

      private

      def self.coerce_with_true(value)
        "class_method: #{value}"
      end

      def self.coerce_no_coercion(value)
        fail "Should never get here"
      end
    end

    it "does not call coercion methods by default" do
      subject = CoercionTest.new(no_coercion: 'dinklage')
      expect(subject.no_coercion).to eq('dinklage')
    end

    it "calls a class method when coerce: true" do
      subject = CoercionTest.new(with_true: 'peter')
      expect(subject.with_true).to eq('class_method: peter')
    end

    it "calls obj.call when coerce: obj" do
      subject = CoercionTest.new(with_callable: 'daenerys')
      expect(subject.with_callable).to eq('callable: daenerys')
    end

    it "coerces default values" do
      subject = CoercionTest.new
      expect(subject.double_it).to eq('4242')
    end

    it "performs coercion before validation" do
      expect {
        CoercionTest.new(double_it: 6)
      }.to raise_error(
        ValueSemantics::InvalidValue,
        "Attribute `CoercionTest#double_it` is invalid: 12",
      )
    end
  end

  describe 'DSL' do
    it 'allows attributes to end with punctuation' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          qmark?
          bang!
        }
      end
      expect(klass.new(qmark?: 222, bang!: 333)).to have_attributes(
        qmark?: 222,
        bang!: 333,
      )
    end

    it 'has an option for default values' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          moo default: {}
        }
      end
      expect(klass.new.moo).to eq({})
    end

    it 'has a built-in Anything matcher' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          wario Anything()
        }
      end
      expect(klass.new(wario: RSpec).wario).to be(RSpec)
    end

    it 'has a built-in Bool matcher' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          engaged Bool()
        }
      end
      expect(klass.new(engaged: true).engaged).to be(true)
    end

    it 'has a built-in Either matcher' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          woof Either(String, Integer)
        }
      end
      expect(klass.new(woof: 42).woof).to eq(42)
    end

    it 'has a built-in ArrayOf matcher' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          things ArrayOf(String)
        }
      end
      expect(klass.new(things: %w(a b c)).things).to eq(%w(a b c))
    end

    it 'has a built-in HashOf matcher' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          counts HashOf(Symbol => Integer)
        }
      end
      expect(klass.new(counts: {a: 1}).counts).to eq({a: 1})
    end

    it 'raises ArgumentError if the HashOf argument is wrong' do
      expect do
        ValueSemantics.for_attributes {
          counts HashOf({ a: 1, b: 2})
        }
      end.to raise_error(ArgumentError, "HashOf() takes a hash with one key and one value")
    end

    it 'has an option to call a class method for coercion' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          widgets String, coerce: true
        }

        def self.coerce_widgets(widgets)
          case widgets
          when Array then widgets.join('|')
          else widgets
          end
        end
      end

      expect(klass.new(widgets: [1,2,3]).widgets).to eq('1|2|3')
      expect(klass.new(widgets: 'schmidgets').widgets).to eq('schmidgets')
    end

    it 'provides a way to define methods whose names are invalid Ruby syntax' do
      klass = Class.new do
        include ValueSemantics.for_attributes {
          def_attr 'else'
        }
      end
      expect(klass.new(else: 2).else).to eq(2)
    end
  end

  it "has a version number" do
    expect(ValueSemantics::VERSION).not_to be_empty
  end

end
