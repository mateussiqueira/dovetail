Pod::Spec.new do |s|
  s.name             = 'dovetail_shortcut_channel'
  s.version          = '0.1.0'
  s.summary          = 'System-wide keyboard shortcuts for Flutter desktop.'
  s.description      = <<-DESC
Binds a chord the operating system delivers even when no window of the app has
focus, and reports out loud the sessions where no such chord can be granted.
                       DESC
  s.homepage         = 'https://github.com/mateussiqueira/dovetail'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Example Org' => 'mateus.siqueira@ayzen.one' }

  s.platform         = :osx, '10.15'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.frameworks       = 'Carbon', 'AppKit'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust dovetail_shortcut_channel',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libdesktop_shortcut_channel.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libdesktop_shortcut_channel.a',
  }
end
