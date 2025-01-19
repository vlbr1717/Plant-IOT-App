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
      home: BLEHomePage(),
    );
  }
}

class BLEHomePage extends StatefulWidget {
  @override
  _BLEHomePageState createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> {
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
  
  // Add your ESP32's service UUID here
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"; // Replace with your UUID

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() async {
    setState(() {
      devices.clear();
      isScanning = true;
    });

    try {
      // Remove the service UUID filter temporarily for testing
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 5),
        // withServices: [Guid(serviceUuid)], // Comment this out temporarily
      );
      
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          // Add debug printing
          print('Found device: ${r.device.platformName} (${r.device.remoteId})');
          print('RSSI: ${r.rssi}');
          if (r.advertisementData.serviceUuids.isNotEmpty) {
            print('Service UUIDs: ${r.advertisementData.serviceUuids}');
          }
          
          if (!devices.contains(r.device)) {
            setState(() {
              devices.add(r.device);
            });
          }
        }
      });

      // When scan completes
      Future.delayed(Duration(seconds: 5), () {
        stopScan();
      });
    } catch (e) {
      print('Error scanning: $e');
      stopScan();
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    setState(() {
      isScanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("BLE Device Scanner"),
        actions: [
          IconButton(
            icon: Icon(isScanning ? Icons.stop : Icons.refresh),
            onPressed: isScanning ? stopScan : startScan,
          ),
        ],
      ),
      body: devices.isEmpty
          ? Center(
              child: isScanning
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Scanning for devices..."),
                      ],
                    )
                  : Text("No devices found"),
            )
          : ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = devices[index];
                return ListTile(
                  leading: Icon(Icons.bluetooth),
                  title: Text(device.platformName.isNotEmpty ? device.platformName : "Unnamed Device"),
                  subtitle: Text(device.remoteId.toString()),
                  trailing: StreamBuilder<BluetoothConnectionState>(
                    stream: device.connectionState,
                    initialData: BluetoothConnectionState.disconnected,
                    builder: (c, snapshot) {
                      if (snapshot.data == BluetoothConnectionState.connected) {
                        return Icon(Icons.check_circle, color: Colors.green);
                      }
                      return ElevatedButton(
                        child: Text('Connect'),
                        onPressed: () async {
                          try {
                            await device.connect();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DevicePage(device: device),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to connect to device'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class DevicePage extends StatefulWidget {
  final BluetoothDevice device;

  DevicePage({required this.device});

  @override
  _DevicePageState createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  List<BluetoothService> services = [];
  bool isLoading = true;
  String characteristicValue = "No value yet";
  
  // These UUIDs match your ESP32 exactly
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    connectAndRead();
  }

  Future<void> connectAndRead() async {
    try {
      // Discover services
      services = await widget.device.discoverServices();
      
      // Find our specific service and characteristic
      for (BluetoothService service in services) {
        if (service.uuid.toString() == serviceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == characteristicUuid) {
              // Enable notifications
              await characteristic.setNotifyValue(true);
              
              // Listen to the characteristic value updates
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  setState(() {
                    characteristicValue = String.fromCharCodes(value);
                    print('Received value: $characteristicValue');
                  });
                }
              });
              
              // Read the initial value
              final initialValue = await characteristic.read();
              setState(() {
                characteristicValue = String.fromCharCodes(initialValue);
                print('Initial value: $characteristicValue');
              });
            }
          }
        }
      }
      
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() {
        characteristicValue = 'Error reading value: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Device: ${widget.device.platformName}"),
      ),
      body: Center(
        child: isLoading
            ? CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Characteristic Value:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 10),
                  Text(
                    characteristicValue,
                    style: TextStyle(fontSize: 24),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: connectAndRead,
                    child: Text('Refresh Value'),
                  ),
                ],
              ),
      ),
    );
  }
}
