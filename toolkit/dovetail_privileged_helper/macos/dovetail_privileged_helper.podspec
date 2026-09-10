#
# The macOS half of dovetail_privileged_helper.
#
Pod::Spec.new do |s|
  s.name             = 'dovetail_privileged_helper'
  s.version          = '0.1.0'
  s.summary          = 'Privileged helper registration for Flutter, Dovetail toolkit.'
  s.description      = <<-DESC
SMAppService behind a method channel: registers the app's root daemon, reports
whether macOS is holding it for the user's approval, and opens the Login Items
pane where that approval is given. Reports "unsupported" below macOS 13 rather
than falling back to SMJobBless, which has no approval state to report.
                       DESC
  s.homepage         = 'https://github.com/mateussiqueira/dovetail'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mateus Siqueira' => 'mateussiqueira@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.frameworks       = 'ServiceManagement', 'AppKit'

  # 10.14 and not 13, on purpose: this package must not raise the floor of an
  # app that adopts it. Everything SMAppService is guarded by @available, and
  # on an older system the plugin loads and answers "unsupported" — which is
  # a state the Dart side has, precisely so this does not have to be a build
  # error for somebody who supports old Macs.
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
