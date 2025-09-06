# config/initializers/fixnum_compat.rb
Fixnum = Integer unless defined?(Fixnum)  # rubocop:disable Lint/ConstantDefinitionInBlock
Bignum = Integer unless defined?(Bignum)