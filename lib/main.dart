import 'dart:async';
import 'dart:math';
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

class SimulatedDataService {
  Timer? _timer;
  final Random _random = Random();

  double generateValue(String metric) {
    switch (metric) {
      case 'temp':
        return 20.0 + _random.nextDouble() * 15; // 20-35°C
      case 'humidity':
      case 'soil':
      case 'water':
        return _random.nextDouble() * 100; // 0-100%
      case 'light':
        return _random.nextDouble() * 1000; // 0-1000 lux
      case 'rssi':
        return -100 + _random.nextDouble() * 60; // -100 to -40 dBm
      case 'time':
        return _random.nextDouble() * 1000; // 0-1000ms
      default:
        return _random.nextDouble() * 100;
    }
  }

  String generatePlantType() {
    final plants = ['Rose', 'Cactus', 'Fern', 'Orchid', 'Succulent'];
    return plants[_random.nextInt(plants.length)];
  }

  void startSimulation(Function(String metric, String value) onData) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      // Simulate data for each metric
      onData('temp', generateValue('temp').toStringAsFixed(1));
      onData('humidity', generateValue('humidity').toStringAsFixed(1));
      onData('light', generateValue('light').toStringAsFixed(0));
      onData('soil', generateValue('soil').toStringAsFixed(1));
      onData('water', generateValue('water').toStringAsFixed(1));
      onData('rssi', generateValue('rssi').toStringAsFixed(0));
      onData('time', generateValue('time').toStringAsFixed(0));
    });
  }

  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }
}

// Move MetricStats class to top-level (before HomePage class)
class MetricStats {
  final double min;
  final double max;
  final double avg;

  MetricStats({required this.min, required this.max, required this.avg});

  static MetricStats calculateStats(List<FlSpot> data) {
    if (data.isEmpty) {
      return MetricStats(min: 0, max: 0, avg: 0);
    }
    double sum = 0;
    double min = data[0].y;
    double max = data[0].y;
    
    for (var spot in data) {
      sum += spot.y;
      if (spot.y < min) min = spot.y;
      if (spot.y > max) max = spot.y;
    }
    
    return MetricStats(
      min: min,
      max: max,
      avg: sum / data.length,
    );
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
  
  // Update UUIDs to match new structure
  static const String CONNECTION_SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String SENSOR_SERVICE_UUID = "8d0784b6-2223-441a-9816-7739ce86b839";
  static const String PLANT_TYPE_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String TIME_UUID = "15dfb155-438b-4d15-a71a-7d643b6f4f14";
  static const String RSSI_UUID = "9860d00a-0c05-4a93-bdf3-e4ebf89dcbd8";
  static const String SOIL_UUID = "0946b48f-a0f9-42c6-82f5-e68bd2a225c4";
  static const String WATER_UUID = "4b00cc89-ad01-49d2-bd50-fd00211e8637";
  static const String HUMIDITY_UUID = "bcefab83-bc07-4601-bd67-973056e7ab40";
  static const String TEMP_UUID = "021c8554-0292-4781-83db-e0e480d9b447";
  static const String LIGHT_UUID = "71cca481-acbc-47c0-b379-dfc5de3e2db5";
  static const String PUMP_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9"; // Example UUID, replace with your actual pump UUID

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
  };
  int dataPointCounter = 0;
  final int maxDataPoints = 50;

  // Create separate stream controllers for each metric
  final Map<String, StreamController<List<FlSpot>>> _streamControllers = {
    'temp': StreamController<List<FlSpot>>.broadcast(),
    'humidity': StreamController<List<FlSpot>>.broadcast(),
    'light': StreamController<List<FlSpot>>.broadcast(),
    'soil': StreamController<List<FlSpot>>.broadcast(),
    'water': StreamController<List<FlSpot>>.broadcast(),
    'rssi': StreamController<List<FlSpot>>.broadcast(),
  };

  bool isDevelopmentMode = true;
  final SimulatedDataService _simulatedDataService = SimulatedDataService();

  // Add this list at the class level in _HomePageState
  final List<String> plantTypes = ['Rose', 'Cactus', 'Fern', 'Orchid', 'Succulent'];

  // Add a state variable for pump status
  bool isPumpOn = false;

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
    if (isDevelopmentMode) {
      setState(() {
        connectedDevice = device;
        startDevMode();
      });
      return;
    }
    
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
      bool foundConnectionService = false;
      bool foundSensorService = false;
      
      for (BluetoothService service in services) {
        String serviceUuid = service.uuid.toString().toLowerCase();
        
        if (serviceUuid == CONNECTION_SERVICE_UUID.toLowerCase()) {
          foundConnectionService = true;
          // Handle connection service characteristics
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            if ([PLANT_TYPE_UUID.toLowerCase(), 
                 TIME_UUID.toLowerCase(), 
                 RSSI_UUID.toLowerCase()].contains(charUuid)) {
              await setupCharacteristic(characteristic);
            }
          }
        }
        
        if (serviceUuid == SENSOR_SERVICE_UUID.toLowerCase()) {
          foundSensorService = true;
          // Handle sensor service characteristics
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuid = characteristic.uuid.toString().toLowerCase();
            if ([SOIL_UUID.toLowerCase(),
                 WATER_UUID.toLowerCase(),
                 HUMIDITY_UUID.toLowerCase(),
                 TEMP_UUID.toLowerCase(),
                 LIGHT_UUID.toLowerCase()].contains(charUuid)) {
              await setupCharacteristic(characteristic);
            }
          }
        }
      }
      
      if (!foundConnectionService || !foundSensorService) {
        throw Exception('Required services not found');
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

  // Add helper method to setup characteristics
  Future<void> setupCharacteristic(BluetoothCharacteristic characteristic) async {
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

  void disconnect() async {
    _simulatedDataService.stopSimulation();
    if (connectedDevice != null) {
      if (!isDevelopmentMode) {
        await connectedDevice!.disconnect();
      }
      setState(() {
        connectedDevice = null;
        characteristicValue = "No data";
      });
    }
  }

  // Update the _showGraph method
  void _showGraph(String value, String title, Color color) {
    String metricKey = title.toLowerCase().replaceAll(' ', '_')
                           .replaceAll('moisture', '')
                           .replaceAll('level', '')
                           .replaceAll('temperature', 'temp');
    
    List<FlSpot> history = valueHistory[metricKey] ?? [];
    
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
                stream: _streamControllers[metricKey]?.stream,
                initialData: history,
                builder: (context, snapshot) {
                  final data = snapshot.data ?? [];
                  if (data.isEmpty) {
                    return Center(child: Text('No data available'));
                  }

                  // Calculate statistics
                  final stats = MetricStats.calculateStats(data);
                  
                  // Calculate Y-axis range with 10% padding
                  final yPadding = (stats.max - stats.min) * 0.1;
                  final minY = stats.min - yPadding;
                  final maxY = stats.max + yPadding;
                  
                  // Calculate Y-axis interval
                  final yInterval = (maxY - minY) / 5;
                  
                  return Column(
                    children: [
                      Expanded(
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: false,
                                  reservedSize: 30,
                                  interval: 5,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 50,
                                  interval: yInterval,
                                  getTitlesWidget: (value, meta) {
                                    // Skip the first and last labels
                                    if (value == minY || value == maxY) {
                                      return const Text('');
                                    }
                                    return Container(
                                      width: 45,  // Fixed width container
                                      alignment: Alignment.centerRight,  // Right align the text
                                      padding: EdgeInsets.only(right: 8),  // Add some padding from the axis
                                      child: Text(
                                        value.toStringAsFixed(1),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                        textAlign: TextAlign.right,  // Right align the text within the Text widget
                                      ),
                                    );
                                  },
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
                            minX: data.first.x,
                            maxX: data.last.x,
                            minY: minY,
                            maxY: maxY,
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
                        ),
                      ),
                      // Statistics panel
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('Min', stats.min.toStringAsFixed(1), color),
                            _buildStatItem('Avg', stats.avg.toStringAsFixed(1), color),
                            _buildStatItem('Max', stats.max.toStringAsFixed(1), color),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build stat items
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
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
    print('Received data for ${characteristic.uuid}: $data'); // Debug print
    switch (characteristic.uuid.toString().toLowerCase()) {
      case PLANT_TYPE_UUID:
        setState(() {
          plantTypeValue = data.trim();
        });
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
        setState(() {
          lightValue = cleanValue(data, 'light');
          updateHistory('light', cleanValue(data, 'light'));
        });
        break;
    }
  }

  // Update the updateHistory method to properly handle different metrics
  void updateHistory(String metric, String value) {
    try {
      // Remove any non-numeric characters except minus sign and decimal point
      String cleanedValue = value.replaceAll(RegExp(r'[^0-9.-]'), '');
      double numValue = double.parse(cleanedValue);
      
      // Normalize values based on metric type
      switch (metric.toLowerCase()) {
        case 'rssi':
          // RSSI values are typically negative
          numValue = numValue.clamp(-100.0, 0.0);
          break;
        case 'humidity':
        case 'soil':
        case 'water':
          // Percentage values should be between 0-100
          numValue = numValue.clamp(0.0, 100.0);
          break;
        case 'temp':
          // Temperature typically between 0-50°C
          numValue = numValue.clamp(0.0, 50.0);
          break;
        case 'light':
          // Light values can range from 0-1000+ lux
          numValue = numValue.clamp(0.0, 1000.0);
          break;
        case 'time':
          // Time values (in ms) don't need clamping
          break;
      }
      
      List<FlSpot> history = valueHistory[metric.toLowerCase()] ?? [];
      history.add(FlSpot(dataPointCounter.toDouble(), numValue));
      
      // Keep only the last maxDataPoints points
      if (history.length > maxDataPoints) {
        history.removeAt(0);
      }
      
      valueHistory[metric.toLowerCase()] = history;
      _streamControllers[metric.toLowerCase()]?.add(history);
      dataPointCounter++;
    } catch (e) {
      print('Error updating history for $metric with value $value: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plant Monitor'),
        centerTitle: true,
        actions: [
          // Development mode toggle
          Switch(
            value: isDevelopmentMode,
            onChanged: (value) {
              setState(() {
                isDevelopmentMode = value;
                if (isDevelopmentMode) {
                  // Start simulation if in dev mode and not connected to real device
                  if (connectedDevice == null) {
                    startDevMode();
                  }
                } else {
                  // Stop simulation when switching to real mode
                  _simulatedDataService.stopSimulation();
                }
              });
            },
          ),
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
                                  title: 'Temp',
                                  value: tempValue,
                                  unit: '°C',
                                  color: Colors.orange,
                                  onTap: () => _showGraph(tempValue, 'Temp', Colors.orange),
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
                                  title: 'Soil',
                                  value: soilValue,
                                  unit: '%',
                                  color: Colors.green,
                                  onTap: () => _showGraph(soilValue, 'Soil', Colors.green),
                                ),
                                // Water Level Box
                                _buildSensorCard(
                                  icon: Icons.water_outlined,
                                  title: 'Water',
                                  value: waterValue,
                                  unit: '%',
                                  color: Colors.lightBlue,
                                  onTap: () => _showGraph(waterValue, 'Water', Colors.lightBlue),
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
                                // Plant Type Box
                                _buildPlantTypeCard(
                                  icon: Icons.local_florist,
                                  title: 'Plant Type',
                                  value: plantTypeValue,
                                  color: Colors.teal,
                                ),
                                // Add Pump Control where Plant Type was
                                _buildPumpControlCard(
                                  icon: Icons.water_drop,
                                  title: 'Pump Control',
                                  color: Colors.blue,
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

  // Update the _buildSensorCard widget to handle dynamic text sizing
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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value != "N/A" ? value + unit : "N/A",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Update dispose method to close all stream controllers
  @override
  void dispose() {
    _simulatedDataService.stopSimulation();
    for (var controller in _streamControllers.values) {
      controller.close();
    }
    super.dispose();
  }

  void startDevMode() {
    _simulatedDataService.startSimulation((metric, value) {
      setState(() {
        switch (metric) {
          case 'temp':
            tempValue = value;
            updateHistory('temp', value);
            break;
          case 'humidity':
            humidityValue = value;
            updateHistory('humidity', value);
            break;
          case 'light':
            lightValue = value;
            updateHistory('light', value);
            break;
          case 'soil':
            soilValue = value;
            updateHistory('soil', value);
            break;
          case 'water':
            waterValue = value;
            updateHistory('water', value);
            break;
          case 'rssi':
            rssiValue = value;
            updateHistory('rssi', value);
            break;
          case 'time':
            timeValue = value;
            updateHistory('time', value);
            break;
        }
      });
    });
  }

  // Add this new method to build the Plant Type card
  Widget _buildPlantTypeCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell( // Add InkWell for tap feedback
        onTap: () {
          // Show dropdown when card is tapped
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Select Plant Type'),
                content: Container(
                  width: double.minPositive,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: plantTypes.length,
                    itemBuilder: (BuildContext context, int index) {
                      return ListTile(
                        title: Text(
                          plantTypes[index],
                          style: TextStyle(
                            color: plantTypes[index] == plantTypeValue ? color : Colors.black,
                            fontWeight: plantTypes[index] == plantTypeValue ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onTap: () {
                          setState(() {
                            plantTypeValue = plantTypes[index];
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
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
                value != "N/A" ? value : plantTypes[0],
                style: TextStyle(
                  fontSize: 18,
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

  // Add this new method for the pump control card
  Widget _buildPumpControlCard({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            isPumpOn = !isPumpOn;
            if (!isDevelopmentMode && connectedDevice != null) {
              _sendPumpCommand(isPumpOn);
            }
          });
        },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Switch(
                value: isPumpOn,
                onChanged: (bool value) {
                  setState(() {
                    isPumpOn = value;
                    if (!isDevelopmentMode && connectedDevice != null) {
                      _sendPumpCommand(isPumpOn);
                    }
                  });
                },
                activeColor: color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Add method to send pump command via BLE
  Future<void> _sendPumpCommand(bool turnOn) async {
    try {
      if (connectedDevice != null) {
        List<BluetoothService> services = await connectedDevice!.discoverServices();
        for (var service in services) {
          var characteristics = service.characteristics;
          for (BluetoothCharacteristic c in characteristics) {
            if (c.uuid.toString() == PUMP_UUID) {
              await c.write([turnOn ? 1 : 0]);
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Error sending pump command: $e');
    }
  }
}

