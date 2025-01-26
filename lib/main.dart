import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

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
  
  // Make UUIDs constant for switch cases
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String PLANT_TYPE_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String TIME_UUID = "15dfb155-438b-4d15-a71a-7d643b6f4f14";
  static const String RSSI_UUID = "9860d00a-0c05-4a93-bdf3-e4ebf89dcbd8";
  static const String SOIL_UUID = "0946b48f-a0f9-42c6-82f5-e68bd2a225c4";
  static const String WATER_UUID = "4b00cc89-ad01-49d2-bd50-fd00211e8637";
  static const String HUMIDITY_UUID = "bcefab83-bc07-4601-bd67-973056e7ab40";
  static const String TEMP_UUID = "021c8554-0292-4781-83db-e0e480d9b447";
  static const String LIGHT_UUID = "71cca481-acbc-47c0-b379-dfc5de3e2db5";

  // Values for each metric (only declare each variable once)
  String plantTypeValue = "N/A";
  String timeValue = "N/A";
  String rssiValue = "N/A";
  String soilValue = "N/A";
  String waterValue = "N/A";
  String humidityValue = "N/A";  // Only declare once
  String tempValue = "N/A";
  String lightValue = "N/A";

  // Add history tracking for each metric
  Map<String, List<FlSpot>> valueHistory = {
    'temp': [],
    'humidity': [],
    'light': [],
    'soil': [],
    'water': [],
    'rssi': [],
    'time': [],
  };
  int dataPointCounter = 0;
  final int maxDataPoints = 50;

  // Add this stream controller at the top of _HomePageState
  final StreamController<List<FlSpot>> _rssiStreamController = StreamController<List<FlSpot>>.broadcast();

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
        if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          foundService = true;
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            try {
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen((value) {
                if (value.isNotEmpty) {
                  String data = String.fromCharCodes(value);
                  setState(() {
                    handleCharacteristicValue(characteristic, data);
                  });
                }
              });

              // Read initial value
              final initialValue = await characteristic.read();
              setState(() {
                String data = String.fromCharCodes(initialValue);
                handleCharacteristicValue(characteristic, data);
              });
            } catch (e) {
              print('Error setting up characteristic ${characteristic.uuid}: $e');
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

  // Add the _showGraph method
  void _showGraph(String value, String title, Color color) {
    List<FlSpot> history = valueHistory[title.toLowerCase()] ?? [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title History',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<FlSpot>>(
                stream: _rssiStreamController.stream,
                initialData: history,
                builder: (context, snapshot) {
                  final data = snapshot.data ?? [];
                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 5,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            interval: 10,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: true),
                      minX: data.isEmpty ? 0 : data.first.x,
                      maxX: data.isEmpty ? 0 : data.last.x,
                      minY: -100,
                      maxY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: data,
                          isCurved: true,
                          color: color,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withOpacity(0.2),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Update the cleanValue method to also remove duplicate units
  String cleanValue(String value, String type) {
    String cleaned = value;
    cleaned = cleaned.replaceAll('Soil:', '')
                    .replaceAll('RSSI:', '')
                    .replaceAll('Time:', '')
                    .replaceAll('dBm', '')
                    .replaceAll('ms', '')
                    .replaceAll('%', '')
                    .trim();
    return cleaned;
  }

  // Update the handleCharacteristicValue method
  void handleCharacteristicValue(BluetoothCharacteristic characteristic, String data) {
    switch (characteristic.uuid.toString()) {
      case PLANT_TYPE_UUID:
        plantTypeValue = cleanValue(data, 'plant');
        break;
      case TIME_UUID:
        timeValue = cleanValue(data, 'time');
        updateHistory('time', cleanValue(data, 'time'));
        break;
      case RSSI_UUID:
        rssiValue = cleanValue(data, 'rssi');
        updateHistory('rssi', cleanValue(data, 'rssi'));
        break;
      case SOIL_UUID:
        soilValue = cleanValue(data, 'soil');
        updateHistory('soil', cleanValue(data, 'soil'));
        break;
      case WATER_UUID:
        waterValue = cleanValue(data, 'water');
        updateHistory('water', cleanValue(data, 'water'));
        break;
      case HUMIDITY_UUID:
        humidityValue = cleanValue(data, 'humidity');
        updateHistory('humidity', cleanValue(data, 'humidity'));
        break;
      case TEMP_UUID:
        tempValue = cleanValue(data, 'temp');
        updateHistory('temp', cleanValue(data, 'temp'));
        break;
      case LIGHT_UUID:
        lightValue = cleanValue(data, 'light');
        updateHistory('light', cleanValue(data, 'light'));
        break;
    }
  }

  // Add method to update history
  void updateHistory(String metric, String value) {
    try {
      double numValue = double.parse(value);
      List<FlSpot> history = valueHistory[metric] ?? [];
      history.add(FlSpot(dataPointCounter.toDouble(), numValue));
      if (history.length > maxDataPoints) {
        history.removeAt(0);
      }
      valueHistory[metric] = history;
      dataPointCounter++;
      _rssiStreamController.add(history);
    } catch (e) {
      print('Error updating history for $metric: $e');
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
                              ? Container()
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
                                // Temperature Box
                                _buildSensorCard(
                                  icon: Icons.thermostat_outlined,
                                  title: 'Temperature',
                                  value: tempValue,
                                  unit: '°C',
                                  color: Colors.orange,
                                  onTap: () => _showGraph(tempValue, 'Temperature', Colors.orange),
                                ),
                                // Humidity Box
                                _buildSensorCard(
                                  icon: Icons.water_drop_outlined,
                                  title: 'Humidity',
                                  value: humidityValue,
                                  unit: '%',
                                  color: Colors.blue,
                                  onTap: () => _showGraph(humidityValue, 'Humidity', Colors.blue),
                                ),
                                // Light Box
                                _buildSensorCard(
                                  icon: Icons.light_mode_outlined,
                                  title: 'Light',
                                  value: lightValue,
                                  unit: 'lux',
                                  color: Colors.amber,
                                  onTap: () => _showGraph(lightValue, 'Light', Colors.amber),
                                ),
                                // Soil Moisture Box
                                _buildSensorCard(
                                  icon: Icons.grass_outlined,
                                  title: 'Soil Moisture',
                                  value: soilValue,
                                  unit: '%',
                                  color: Colors.green,
                                  onTap: () => _showGraph(soilValue, 'Soil Moisture', Colors.green),
                                ),
                                // Water Level Box
                                _buildSensorCard(
                                  icon: Icons.water_outlined,
                                  title: 'Water Level',
                                  value: waterValue,
                                  unit: '%',
                                  color: Colors.lightBlue,
                                  onTap: () => _showGraph(waterValue, 'Water Level', Colors.lightBlue),
                                ),
                                // RSSI Box
                                _buildSensorCard(
                                  icon: Icons.signal_cellular_alt,
                                  title: 'RSSI',
                                  value: rssiValue,
                                  unit: 'dBm',
                                  color: Colors.purple,
                                  onTap: () => _showGraph(rssiValue, 'RSSI', Colors.purple),
                                ),
                                // Time Box
                                _buildSensorCard(
                                  icon: Icons.access_time,
                                  title: 'Time',
                                  value: timeValue,
                                  unit: 'ms',
                                  color: Colors.grey,
                                  onTap: () => _showGraph(timeValue, 'Time', Colors.grey),
                                ),
                                // Plant Type Box
                                _buildSensorCard(
                                  icon: Icons.local_florist,
                                  title: 'Plant Type',
                                  value: plantTypeValue,
                                  unit: '',
                                  color: Colors.teal,
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

  // Update the _buildSensorCard widget
  Widget _buildSensorCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
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
                value != "N/A" ? value + unit : "N/A",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add dispose method to clean up the stream controller
  @override
  void dispose() {
    _rssiStreamController.close();
    super.dispose();
  }
}

