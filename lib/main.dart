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

  @override
  void initState() {
    super.initState();
    discoverServices();
  }

  Future<void> discoverServices() async {
    final bleService = BLEService();
    final discoveredServices = await bleService.discoverServices(widget.device);
    
    setState(() {
      services = discoveredServices;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Device: ${widget.device.platformName}"),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: services.length,
              itemBuilder: (context, index) {
                final service = services[index];
                return ExpansionTile(
                  title: Text('Service: ${service.uuid}'),
                  children: service.characteristics.map((c) {
                    return ListTile(
                      title: Text('Characteristic: ${c.uuid}'),
                      subtitle: Text('Properties: ${c.properties.toString()}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (c.properties.read)
                            IconButton(
                              icon: Icon(Icons.refresh),
                              onPressed: () async {
                                await c.read();
                              },
                            ),
                          if (c.properties.write)
                            IconButton(
                              icon: Icon(Icons.edit),
                              onPressed: () {
                                // Add write functionality here
                              },
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
