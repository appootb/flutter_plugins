#
Pod::Spec.new do |s|
  s.name             = 'advanced_clipboard'
  s.version          = '0.0.1'
  s.summary          = 'Advanced Flutter clipboard helpers.'
  s.description      = <<-DESC
Cross-platform clipboard read/write and snapshot API for richer payloads.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Appootb' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'advanced_clipboard/Sources/advanced_clipboard/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
