# Optimize JSON handling with Oj if present.
if defined?(Oj)
  # Use Rails compatibility mode and fastest options.
  Oj.optimize_rails
end

