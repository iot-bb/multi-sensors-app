import 'dart:async';

import 'package:barcode_scan/barcode_scan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  runApp(new MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String barcode = "";
  FlutterBlue _flutterBlue = FlutterBlue.instance;

  /// Scanning
  StreamSubscription _scanSubscription;
  Map<DeviceIdentifier, ScanResult> scanResults = new Map();
  bool isScanning = false;

  /// State
  StreamSubscription _stateSubscription;
  BluetoothState state = BluetoothState.unknown;

  /// Device
  BluetoothDevice device;
  bool get isConnected => (device != null);
  StreamSubscription deviceConnection;
  StreamSubscription deviceStateSubscription;
  List<BluetoothService> services = new List();
  Map<Guid, StreamSubscription> valueChangedSubscriptions = {};
  BluetoothDeviceState deviceState = BluetoothDeviceState.disconnected;

  BluetoothCharacteristic characteristic;

  var params = [];
  var data = "";
  @override
  void initState() {
    super.initState();
    // Immediately get the state of FlutterBlue
    _flutterBlue.state.then((s) {
      setState(() {
        state = s;
      });
    });
    // Subscribe to state changes
    _stateSubscription = _flutterBlue.onStateChanged().listen((s) {
      setState(() {
        state = s;
      });
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;
    super.dispose();
  }

  Future scan() async {
    try {
      String barcode = await BarcodeScanner.scan();
      setState(() => this.barcode = barcode);
    } on PlatformException catch (e) {
      if (e.code == BarcodeScanner.CameraAccessDenied) {
        setState(() {
          this.barcode = 'The user did not grant the camera permission!';
        });
      } else {
        setState(() => this.barcode = 'Unknown error: $e');
      }
    } on FormatException{
      setState(() => this.barcode = 'null (User returned using the "back"-button before scanning anything. Result)');
    } catch (e) {
      setState(() => this.barcode = 'Unknown error: $e');
    }
  }

  _startScan() {
    _scanSubscription = _flutterBlue.scan(
      timeout: const Duration(seconds: 5),
    ).listen((scanResult) {
      print('localName: ${scanResult.advertisementData.localName}');
      setState(() {
        scanResults[scanResult.device.id] = scanResult;
        if (params.length == 3) {
          if (params[0] == scanResult.device.id.toString() && isConnected == false) {
            _stopScan();
            _connect(scanResult.device);
          }
        }
      });
    }, onDone: _stopScan);

    setState(() {
      isScanning = true;
    });
  }

  _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    barcode = "";
    setState(() {
      isScanning = false;
    });
  }

  _disconnect() {
    // Remove all value changed listeners
    valueChangedSubscriptions.forEach((uuid, sub) => sub.cancel());
    valueChangedSubscriptions.clear();
    deviceStateSubscription?.cancel();
    deviceStateSubscription = null;
    deviceConnection?.cancel();
    deviceConnection = null;
    barcode = "";
    setState(() {
      device = null;
    });
  }
  _connect(BluetoothDevice d) async {
    device = d;
    // Connect to device
    deviceConnection = _flutterBlue
        .connect(device, timeout: const Duration(seconds: 4))
        .listen(
      null,
      onDone: null,
    );

    // Update the connection state immediately
    device.state.then((s) {
      setState(() {
        deviceState = s;
      });
    });

    // Subscribe to connection changes
    deviceStateSubscription = device.onStateChanged().listen((s) {
      setState(() {
        deviceState = s;
      });
      if (s == BluetoothDeviceState.connected) {
        device.discoverServices().then((s) {
          setState(() {
            services = s;
          });
        });
      }
    });
  }

  _setNotification(BluetoothCharacteristic c) async {
//    print("=================" + c.isNotifying.toString());
    if (c.isNotifying) {
      await device.setNotifyValue(c, false);
      // Cancel subscription
      valueChangedSubscriptions[c.uuid]?.cancel();
      valueChangedSubscriptions.remove(c.uuid);
    } else {
      await device.setNotifyValue(c, true);
      // ignore: cancel_subscriptions
      final sub = device.onValueChanged(c).listen((d) {
        setState(() {
          print('onValueChanged: ' + d.first.toString());
          data = d.first.toString();
        });
      });
      // Add to map
      valueChangedSubscriptions[c.uuid] = sub;
    }
    setState(() {});
  }

  List <Widget> buildDeviceListView() {
    return scanResults.values
        .map((r) => Container(
              child: RaisedButton(
                onPressed: () => _connect(r.device),
                child: Text(r.advertisementData.localName),
                color: Colors.blue,
                textColor: Colors.white,
                splashColor: Colors.blueGrey,
              ),
            padding: EdgeInsets.all(10.0),
      )
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    Column column;
    if (barcode.isNotEmpty) {
      params = barcode.split(',');
      print("BarCode: " + barcode);
      if (params.length == 3) {
        _startScan();
        barcode = "";
      }
    }
    if (isConnected) {
      if (device != null) {
        device.discoverServices().then((services) {
          services.forEach((service) {
            service.characteristics.forEach((char) {
              characteristic = char;
              print("===== characteristic: " + characteristic.uuid.toString());
              if (characteristic.properties.notify) {
                _setNotification(characteristic);
              }
            });
          });
        });
      }
      column = new Column(children: <Widget>[
        Container( child: Text(data, style: TextStyle(fontSize: 200),),),
        Container(child: RaisedButton(
            onPressed: () => _disconnect(), child: new Text("Disconnect")
          ),
          padding: EdgeInsets.all(10.0),
        ),

      ],);
    } else {
      column = new Column(
        children: <Widget>[
          new Container(
            child: new RaisedButton(
                onPressed: scan, child: new Text("Scan QR Code")),
            padding: const EdgeInsets.all(8.0),
          ),
          new Container(
            child: new RaisedButton(
                onPressed: _startScan, child: new Text("Search Device")),
            padding: const EdgeInsets.all(8.0),
          ),
          scanResults != null ? new Flexible(child: new ListView(children: buildDeviceListView())) : new Container()
        ],
      );
    }
    return new MaterialApp(
      home: new Scaffold(
          appBar: new AppBar(
            title: new Text('Multi Sensors', style: TextStyle(color: Colors.black),),
            backgroundColor: Colors.amber,
          ),
          body: new Center(
            child: column,
          )),
    );
  }
}