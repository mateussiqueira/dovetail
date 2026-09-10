#
# O nativo de macOS deste pacote, que ate 09/09/2026 nao existia.
#
# O pacote e uma fachada sobre plugins do pub.dev, e o unico nativo proprio
# dele era C++ de Windows. A sonda de aparencia nao tinha como ser fachada: nao
# ha plugin que responda "o sistema nao tem preferencia" — todos colapsam esse
# caso em claro, que e justamente o que se queria distinguir.
#
Pod::Spec.new do |s|
  s.name             = 'dovetail_platform_channel'
  s.version          = '0.1.0'
  s.summary          = 'Desktop platform surface for Flutter, Dovetail toolkit.'
  s.description      = <<-DESC
The macOS half of the Dovetail desktop platform channel. Today it carries one
symbol: the system appearance probe, which distinguishes "the system asked for
light" from "the system did not ask", a difference Flutter's platformBrightness
cannot express.
                       DESC
  s.homepage         = 'https://github.com/mateussiqueira/dovetail'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Mateus Siqueira' => 'mateussiqueira@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # O header e compartilhado com Windows e Linux, e mora fora de macos/.
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../include/dovetail_platform_channel"',
  }
end
