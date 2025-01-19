import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  Future<List<BluetoothService>> discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    return services;
  }
  
  Future<void> writeCharacteristic(
    BluetoothCharacteristic characteristic,
    List<int> value
  ) async {
    await characteristic.write(value);
  }
  
  Stream<List<int>> readCharacteristic(BluetoothCharacteristic characteristic) {
    return characteristic.lastValueStream;
  }
}

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? connectedDevice;
  String characteristicValue = "No data";
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  void startScan() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 4),
        // Removed service UUID filter to show all devices
      );

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });
      });

      // Stop scanning after timeout
      Future.delayed(Duration(seconds: 4), () {
        FlutterBluePlus.stopScan();
        setState(() {
          isScanning = false;
        });
      });

    } catch (e) {
      print('Error scanning: $e');
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
      });
      
      // Discover services and start reading characteristic
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == characteristicUuid) {
              // Enable notifications
              await characteristic.setNotifyValue(true);
              
              // Listen to updates
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  setState(() {
                    characteristicValue = String.fromCharCodes(value);
                  });
                }
              });
              
              // Read initial value
              final initialValue = await characteristic.read();
              setState(() {
                characteristicValue = String.fromCharCodes(initialValue);
              });
            }
          }
        }
      }
      
      setState(() {
        isScanning = false;
      });

    } catch (e) {
      print('Error connecting: $e');
      setState(() {
        isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect')),
      );
    }
  }

  void disconnect() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        characteristicValue = "No data";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plant Monitor'),
        centerTitle: true,
        actions: [
          if (!isScanning && connectedDevice == null)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: startScan,
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Status Card
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      connectedDevice != null 
                          ? Icons.bluetooth_connected 
                          : Icons.bluetooth_disabled,
                      size: 50,
                      color: connectedDevice != null ? Colors.green : Colors.grey,
                    ),
                    SizedBox(height: 8),
                    Text(
                      connectedDevice != null
                          ? 'Connected to: ${connectedDevice!.platformName}'
                          : 'Not Connected',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 16),
                    if (connectedDevice != null)
                      ElevatedButton(
                        onPressed: disconnect,
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text('Disconnect', style: TextStyle(fontSize: 16)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // Device List or Sensor Data
            Expanded(
              child: connectedDevice == null
                  ? Card(
                      elevation: 4,
                      child: isScanning
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Scanning for devices...'),
                                ],
                              ),
                            )
                          : scanResults.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('No devices found'),
                                      SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: startScan,
                                        child: Text('Scan Again'),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: scanResults.length,
                                  itemBuilder: (context, index) {
                                    final result = scanResults[index];
                                    return ListTile(
                                      title: Text(
                                        result.device.platformName.isEmpty
                                            ? 'Unknown Device'
                                            : result.device.platformName,
                                      ),
                                      subtitle: Text(result.device.remoteId.toString()),
                                      trailing: ElevatedButton(
                                        child: Text('Connect'),
                                        onPressed: () => connectToDevice(result.device),
                                      ),
                                    );
                                  },
                                ),
                    )
                  : Card(
                      elevation: 4,
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sensor Data',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 16),
                            Expanded(
                              child: Center(
                                child: Text(
                                  characteristicValue,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
