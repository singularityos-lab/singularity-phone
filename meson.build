project('singularity-phone', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-phone"', language: 'c')
subdir('po')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')
gio_dep  = dependency('gio-2.0')
json_dep = dependency('json-glib-1.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)
system_dep = dependency('singularity-system-1.0',
  fallback: ['libsingularity', 'libsingularity_system_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

if system_dep.type_name() == 'internal'
  system_vapi_dir = join_paths(meson.current_source_dir(), 'subprojects', 'libsingularity', 'src', 'vapi')
  add_project_arguments(['--vapidir=' + system_vapi_dir], language: 'vala')
endif

deps = [gtk_dep, gee_dep, gio_dep, json_dep, libsingularity_dep, system_dep]

core = files(
  'src/call_log.vala',
)

executable('singularity-phone',
  core + files(
    'src/keypad.vala',
    'src/window.vala',
    'src/app.vala',
    'src/hub_bridge.vala',
    'src/agent_intents.vala',
  ),
  dependencies: deps,
  install: true
)

voice_test = executable('voice-test', core + files('tests/voice_test.vala'), dependencies: deps)
test('voice', voice_test, env: ['PHONE_TEST_DIR=' + meson.current_build_dir()])

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.phone.service.in',
  output: 'dev.sinty.phone.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.phone.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/icons/dev.sinty.phone.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

iride = find_program('iride', required: get_option('iride'))
if iride.found()
  custom_target('iride-icon',
    input: 'data/icons/iride/iride.json',
    output: 'dev.sinty.phone.iride',
    depend_files: files(
      'data/icons/iride/layers/000.svg',
      'data/icons/iride/layers/001.svg',
      'data/icons/iride/layers/002.svg',
      'data/icons/iride/layers/003.svg',
      'data/icons/iride/layers/004.svg',
      'data/icons/iride/layers/005.svg',
      'data/icons/iride/layers/006.svg',
      'data/icons/iride/layers/007.svg',
    ),
    command: [iride, 'build', meson.current_source_dir() / 'data' / 'icons' / 'iride', '@OUTPUT@'],
    install: true,
    install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
  )
endif

install_data('data/icons/dev.sinty.phone-keypad-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps'
)
