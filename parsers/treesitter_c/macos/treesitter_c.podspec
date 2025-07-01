Pod::Spec.new do |s|
  s.name             = 'treesitter_c'
  s.version          = '0.0.1'
  s.summary          = 'Tree-sitter parser for c'
  s.description      = 'Auto-generated parser wrapper for c.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Generated' => 'noreply@example.com' }
  s.source           = { :git => 'https://example.com/repo.git', :tag => 'v0.0.1' }
  s.platform         = :macos, '12.0'
  s.vendored_frameworks = 'tree_sitter_c.xcframework'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
