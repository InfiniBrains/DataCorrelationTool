import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:example_flutter/keyboard_test_page.dart';
import 'package:file_chooser/file_chooser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'package:window_size/window_size.dart' as window_size;

// The shared_preferences key for the testbed's color.
const _prefKeyColor = 'color';

void main() {
  // Try to resize and reposition the window to be half the width and height
  // of its screen, centered horizontally and shifted up from center.
  WidgetsFlutterBinding.ensureInitialized();
  window_size.getWindowInfo().then((window) {
    if (window.screen != null) {
      final screenFrame = window.screen.visibleFrame;
      final width = math.max((screenFrame.width / 2).roundToDouble(), 800.0);
      final height = math.max((screenFrame.height / 2).roundToDouble(), 600.0);
      final left = ((screenFrame.width - width) / 2).roundToDouble();
      final top = ((screenFrame.height - height) / 3).roundToDouble();
      final frame = Rect.fromLTWH(left, top, width, height);
      window_size.setWindowFrame(frame);
      window_size
          .setWindowTitle('Flutter Data Correlation Tool for ${Platform.operatingSystem}');

      if (Platform.isMacOS) {
        window_size.setWindowMinSize(Size(800, 600));
        window_size.setWindowMaxSize(Size(1600, 1200));
      }
    }
  });

  runApp(new MyApp());
}

/// Top level widget for the application.
class MyApp extends StatefulWidget {
  /// Constructs a new app with the given [key].
  const MyApp({Key key}) : super(key: key);

  @override
  _AppState createState() => new _AppState();
}

class _AppState extends State<MyApp> {
  _AppState() {
    if (Platform.isMacOS) {
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.containsKey(_prefKeyColor)) {
          setPrimaryColor(Color(prefs.getInt(_prefKeyColor)));
        }
      });
    }
    data = Map();
    cov = Map();
    cor = Map();
  }

  Color _primaryColor = Colors.blue;
  int _counter = 0;

  static _AppState of(BuildContext context) =>
      context.findAncestorStateOfType<_AppState>();

  /// Sets the primary color of the app.
  void setPrimaryColor(Color color) {
    setState(() {
      _primaryColor = color;
    });
    _saveColor();
  }

  void _saveColor() async {
    if (Platform.isMacOS) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyColor, _primaryColor.value);
    }
  }

  void incrementCounter() {
    _setCounter(_counter + 1);
  }

  void _decrementCounter() {
    _setCounter(_counter - 1);
  }

  void _setCounter(int value) {
    setState(() {
      _counter = value;
    });
  }

  Future<void> openCsvDialog() async{
    String initialDirectory;
    if (Platform.isMacOS || Platform.isWindows) {
      initialDirectory =
          (await getApplicationDocumentsDirectory()).path;
    }
    final result = await showOpenPanel(
        initialDirectory: initialDirectory,
        allowedFileTypes: <FileTypeFilterGroup>[
          FileTypeFilterGroup(label: 'CSV', fileExtensions: <String>['csv'])
        ]
    );
    try {
      final text = _resultTextForFileChooserOperation(_FileChooserType.open, result);
      print(text);
    } catch (ex){}
    if(result.paths.isNotEmpty)
      await processCsvfile(result.paths[0]);
  }

  Map<String,List<num>> data;
  Map<String, Map<String,num>> cov;
  Map<String, Map<String,num>> cor;

  Future<void> processCsvfile(String path) async{
    var fileDataContent = await (new File(path)).readAsString();
    var lines = fileDataContent.split('\n');
    data.clear();
    for(var line in lines){
      var cols = line.split(',');
      data[cols[0]] = []; // name of the line
      for(var i=1; i<cols.length; i++)
        data[cols[0]].add(num.parse(cols[i])); // put elements
    }

    processData();
  }

  Future<void> processData() async {
    print("calculating logs");
    await processLog2Data();
    // todo: zscore
    // todo: norm distrib replacement
    print("calculating covs");
    await processCovData();
    print("calculating cors");
    await processCorData();
    print("done");
  }

  Future<void> processLog2Data() async {
    for(var key in data.keys) {
      for(var i=0; i<data[key].length; i++) {
        data[key][i] = math.log(data[key][i])/math.log2e;
      }
    }
  }

  double mean(List<num>arr) {
    num sum = 0.0;
    for(num e in arr)
      sum += e;
    return sum/arr.length;
  }

  double stdev(List<num>arr){
    var sum=0.0;
    var m = mean(arr);
    for(num x in arr) {
      sum += (x-m)*(x-m);
    }
    return math.sqrt(sum/(arr.length -1));
  }

  Future<void> processCovData() async {
    cov.clear();
    for(int j=0; j<data.keys.length; j++) {
      var keyj = data.keys.elementAt(j); // todo: elementAt is not efficient
      cov[keyj] = Map();

      var arrayj = data[keyj];
      var meanj = mean(arrayj);

      for(int i=0;i<data.keys.length;i++) { // todo: make it start from 0
        var keyi = data.keys.elementAt(i); // todo: elementAt is not efficient
        var arrayi = data[keyi];
        var meani = mean(arrayi);

        var sum=0.0;
        for(int x=0;x<arrayi.length;x++)
          sum+=(arrayi[x]-meani)*(arrayj[x]-meanj);

        cov[keyj][keyi]=sum/(arrayi.length-1); // cov number
//        cov[keyj][keyi]=cov[keyi][keyj];
      }
    }
  }

  Future<void> processCorData() async {
    cor.clear();
    for(int j=0; j<data.keys.length; j++) {
      var keyj = data.keys.elementAt(j); // todo: elementAt is not efficient
      cor[keyj] = Map();

      var arrayj = data[keyj];
      var stdevj = stdev(arrayj);

      for(int i=0;i<data.keys.length;i++) { // todo: make it start from j
        var keyi = data.keys.elementAt(i); // todo: elementAt is not efficient
        var arrayi = data[keyi];
        var stdevi = stdev(arrayi);

        cor[keyj][keyi]=cov[keyj][keyi]/(stdevi*stdevj); // cov number
//        cor[keyj][keyi]=cor[keyi][keyj];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Correlation Tool',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: _primaryColor,
        accentColor: _primaryColor,
        // Specify a font to reduce potential issues with the
        // application behaving differently on different platforms.
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text("Data Correlation Tool"),
          actions: <Widget>[],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                child: Text('Data Correlation Tool'),
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
              ),
              ListTile(
                title: Text('Open'),
                onTap: openCsvDialog,
              ),
            ],
          ),
        ),
        body: LayoutBuilder(
          builder: (context, viewportConstraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints:
                BoxConstraints(minHeight: viewportConstraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A widget containing controls to test the file chooser plugin.
class FileChooserTestWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ButtonBar(
      alignment: MainAxisAlignment.center,
      children: <Widget>[
        new FlatButton(
          child: const Text('SAVE'),
          onPressed: () {
            showSavePanel(suggestedFileName: 'save_test.txt').then((result) {
              Scaffold.of(context).showSnackBar(SnackBar(
                content: Text(_resultTextForFileChooserOperation(
                    _FileChooserType.save, result)),
              ));
            });
          },
        ),
        new FlatButton(
          child: const Text('OPEN'),
          onPressed: () async {
            String initialDirectory;
            if (Platform.isMacOS || Platform.isWindows) {
              initialDirectory =
                  (await getApplicationDocumentsDirectory()).path;
            }
            final result = await showOpenPanel(
                allowsMultipleSelection: true,
                initialDirectory: initialDirectory);
            Scaffold.of(context).showSnackBar(SnackBar(
                content: Text(_resultTextForFileChooserOperation(
                    _FileChooserType.open, result))));
          },
        ),
        new FlatButton(
          child: const Text('OPEN MEDIA'),
          onPressed: () async {
            final result =
            await showOpenPanel(allowedFileTypes: <FileTypeFilterGroup>[
              FileTypeFilterGroup(label: 'Images', fileExtensions: <String>[
                'bmp',
                'gif',
                'jpeg',
                'jpg',
                'png',
                'tiff',
                'webp',
              ]),
              FileTypeFilterGroup(label: 'Video', fileExtensions: <String>[
                'avi',
                'mov',
                'mpeg',
                'mpg',
                'webm',
              ]),
            ]);
            Scaffold.of(context).showSnackBar(SnackBar(
                content: Text(_resultTextForFileChooserOperation(
                    _FileChooserType.open, result))));
          },
        ),
      ],
    );
  }
}

/// A widget containing controls to test the url launcher plugin.
class URLLauncherTestWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ButtonBar(
      alignment: MainAxisAlignment.center,
      children: <Widget>[
        new FlatButton(
          child: const Text('OPEN ON GITHUB'),
          onPressed: () {
            url_launcher
                .launch('https://github.com/google/flutter-desktop-embedding');
          },
        ),
      ],
    );
  }
}

/// A widget containing controls to test text input.
class TextInputTestWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const <Widget>[
        SampleTextField(),
        SampleTextField(),
      ],
    );
  }
}

/// A text field with styling suitable for including in a TextInputTestWidget.
class SampleTextField extends StatelessWidget {
  /// Creates a new sample text field.
  const SampleTextField();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200.0,
      padding: const EdgeInsets.all(10.0),
      child: TextField(
        decoration: InputDecoration(border: OutlineInputBorder()),
      ),
    );
  }
}

/// Possible file chooser operation types.
enum _FileChooserType { save, open }

/// Returns display text reflecting the result of a file chooser operation.
String _resultTextForFileChooserOperation(
    _FileChooserType type, FileChooserResult result) {
  if (result.canceled) {
    return '${type == _FileChooserType.open ? 'Open' : 'Save'} cancelled';
  }
  final typeString = type == _FileChooserType.open ? 'opening' : 'saving';
  return 'Selected for $typeString: ${result.paths.join('\n')}';
}
