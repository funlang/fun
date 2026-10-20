fun package()
  result = [
    name: 'package-demo',
    version: '0.1.0',
    bin: 'src/main.fun',
    lib: '',
    'fun': '9.4',

    dependencies: [
      // A path dependency: used in place, no git or network needed.
      'hello': [source: 'libs/hello']
    ],

    // >>> generated - do not edit; run 'fun package tidy' to refresh
    resolved: []
    // <<< generated
  ];
end fun;
