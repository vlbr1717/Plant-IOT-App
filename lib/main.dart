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
  String temperatureValue = "N/A";
  String humidityValue = "N/A";
  
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  void startScan() async {
    setState(() {
      isScanning = true;
      scanResults.clear();
    });

    // Disconnect any existing device
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        characteristicValue = "No data";
      });
    }

    try {
      // Stop any existing scan
      await FlutterBluePlus.stopScan();
      await Future.delayed(Duration(milliseconds: 500));

      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 4),
        androidUsesFineLocation: true,
      );

      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });
      });

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
      // First disconnect any existing connections
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
        setState(() {
          connectedDevice = null;
          characteristicValue = "No data";
        });
      }

      // Add a delay before connecting
      await Future.delayed(Duration(milliseconds: 500));

      // Connect with auto-connect set to false and timeout
      await device.connect(
        timeout: Duration(seconds: 5),
        autoConnect: false,
      ).catchError((error) {
        print('Connection error: $error');
        throw error;
      });

      setState(() {
        connectedDevice = device;
      });

      // Add delay before service discovery
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      bool foundService = false;
      
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          foundService = true;
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
              try {
                // Disable notifications first
                await characteristic.setNotifyValue(false);
                await Future.delayed(Duration(milliseconds: 500));
                
                // Then enable notifications
                await characteristic.setNotifyValue(true);
                
                // Listen to updates
                characteristic.lastValueStream.listen(
                  (value) {
                    if (value.isNotEmpty) {
                      String data = String.fromCharCodes(value);
                      print('Received BLE data: $data');
                      setState(() {
                        characteristicValue = data;
                        // Parse RSSI and Time values
                        if (data.contains('RSSI:') && data.contains('Time:')) {
                          final rssiMatch = RegExp(r'RSSI: ([-\d]+)').firstMatch(data);
                          if (rssiMatch != null) {
                            temperatureValue = rssiMatch.group(1)!;
                          }
                          final timeMatch = RegExp(r'Time:(\d+)ms').firstMatch(data);
                          if (timeMatch != null) {
                            humidityValue = timeMatch.group(1)!;
                          }
                        }
                      });
                    }
                  },
                  onError: (error) {
                    print('Notification error: $error');
                  },
                );
                
                // Read initial value
                try {
                  final initialValue = await characteristic.read();
                  setState(() {
                    characteristicValue = String.fromCharCodes(initialValue);
                  });
                } catch (e) {
                  print('Error reading initial value: $e');
                }
              } catch (e) {
                print('Error setting up characteristic: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error setting up notifications')),
                );
              }
            }
          }
        }
      }
      
      if (!foundService) {
        throw Exception('Required service not found');
      }
      
      setState(() {
        isScanning = false;
      });

    } catch (e) {
      print('Error connecting: $e');
      setState(() {
        isScanning = false;
        connectedDevice = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: ${e.toString()}')),
      );
      // Try to disconnect in case of partial connection
      try {
        await device.disconnect();
      } catch (e) {
        print('Error disconnecting: $e');
      }
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
            // Updated Connection Status Card
            if (connectedDevice == null)
              Card(
                elevation: 4,
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 64,
                        color: Colors.blue,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Connect to Plant Monitor',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: Icon(Icons.search),
                        label: Text('Start Scanning'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: startScan,
                      ),
                    ],
                  ),
                ),
              ),

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
                  : Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connected to: ${connectedDevice!.platformName}',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 16),
                          Expanded(
                            child: GridView.count(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              children: [
                                // Temperature Card (showing RSSI)
                                _buildSensorCard(
                                  icon: Icons.thermostat_outlined,
                                  title: 'RSSI',
                                  value: temperatureValue,
                                  unit: ' dBm',
                                  color: Colors.orange,
                                ),
                                // Humidity Card (showing Time)
                                _buildSensorCard(
                                  icon: Icons.water_drop_outlined,
                                  title: 'Time',
                                  value: humidityValue,
                                  unit: ' ms',
                                  color: Colors.blue,
                                ),
                                // Light Card
                                _buildSensorCard(
                                  icon: Icons.light_mode_outlined,
                                  title: 'Light',
                                  value: 'N/A',
                                  unit: 'lux',
                                  color: Colors.amber,
                                ),
                                // Soil Moisture Card
                                _buildSensorCard(
                                  icon: Icons.grass_outlined,
                                  title: 'Soil Moisture',
                                  value: 'N/A',
                                  unit: '%',
                                  color: Colors.green,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),
                          Center(
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.bluetooth_disabled),
                              label: Text('Disconnect'),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              onPressed: disconnect,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '$value$unit',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
