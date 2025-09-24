import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Configurar Aromatizador',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;
  bool isConnected = false;
  // Removido o status fixo

  // Configurações
  final serviceUUID = "4c656f6e-6172-646f-416c-766573000000";
  final rxUUID = "4c656f6e-6172-646f-416c-766573000001";
  final txUUID = "4c656f6e-6172-646f-416c-766573000002";

  // Controles de formulário - Dias úteis (segunda a sexta)
  TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = const TimeOfDay(hour: 15, minute: 0);
  
  // Controles de formulário - Final de semana (sábado e domingo)
  TimeOfDay weekendStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay weekendEndTime = const TimeOfDay(hour: 14, minute: 0);
  
  int interval = 300; // 5 minutos em segundos
  int sprayDuration = 15; // segundos
  List<bool> weekDays = List.generate(7, (index) => true);

  final List<String> diasSemana = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
  ];

  // Novo método para selecionar dispositivo
  Future<void> selectDevice() async {
    await disconnectDevice(); // <- sempre desconecta antes
    final BluetoothDevice? selectedDevice = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DevicesScreen()),
    );
    if (selectedDevice != null) {
      await connectToDevice(selectedDevice);
    }
  }

  Future<void> initBluetooth() async {
    // Verifica permissões primeiro
    if (!await FlutterBluePlus.isSupported) {
      print("Bluetooth não suportado");
      return;
    }

    // Inicia scan
    try {
      await FlutterBluePlus.turnOn();

      // Aguarda o adaptador estar pronto
      await FlutterBluePlus.adapterState.first;

      // Solicita permissões
      await pedirPermissoesBluetooth(context);

      // Inicia o scan
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: 4),
        androidUsesFineLocation: true,
      );

      // Escuta resultados
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName == 'HomeLoft') {
            FlutterBluePlus.stopScan();
            connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      print('Erro ao iniciar scan: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice d) async {
    if (device != null) return;

    setState(() => device = d);
    await device?.connect();

    // Descobre serviços
    List<BluetoothService> services = await device!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == serviceUUID) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == txUUID) {
            txCharacteristic = characteristic;
          }
          if (characteristic.uuid.toString() == rxUUID) {
            rxCharacteristic = characteristic;
          }
        }
      }
    }

    setState(() => isConnected = true);
  }

  Future<void> sendConfig() async {
    if (!isConnected || rxCharacteristic == null) {
      print('Não conectado ou characteristic não encontrada');
      return;
    }

    // Calcula bitmask dos dias da semana
    int daysMask = 0;
    for (int i = 0; i < 7; i++) {
      if (weekDays[i]) daysMask |= (1 << i);
    }

    // Configuração com horários separados para dias úteis e final de semana
    // Formato: GET /4,daysMask,interval,sprayDuration,weekdayStartH,weekdayStartM,weekdayEndH,weekdayEndM,weekendStartH,weekendStartM,weekendEndH,weekendEndM,
    String config =
        'GET /4,$daysMask,$interval,$sprayDuration,${startTime.hour},${startTime.minute},${endTime.hour},${endTime.minute},${weekendStartTime.hour},${weekendStartTime.minute},${weekendEndTime.hour},${weekendEndTime.minute},';

    print('Enviando: $config');

    try {
      // Primeiro sincroniza o horário (sem mostrar mensagem)
      await sendCurrentTimeQuiet();

      // Depois envia a configuração
      await rxCharacteristic!.write(
        utf8.encode(config),
        withoutResponse: false,
      );
      print('Configuração enviada via BLE!');
      _showConfigSuccessDialog(context);
    } catch (e) {
      print('Erro ao enviar configuração: $e');
      setState(() => isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bluetooth desconectado! Conecte novamente ao dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> sendCurrentTime() async {
    if (!isConnected || rxCharacteristic == null) {
      print('Não conectado ou characteristic não encontrada');
      return;
    }
    int unixTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    String payload = 'UT$unixTime';
    print('Enviando horário: $payload');
    try {
      await rxCharacteristic!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );
      print('Horário enviado via BLE!');
      _showSuccessDialog(context);
    } catch (e) {
      print('Erro ao enviar horário: $e');
      setState(() => isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bluetooth desconectado! Conecte novamente ao dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> sendCurrentTimeQuiet() async {
    if (!isConnected || rxCharacteristic == null) {
      print('Não conectado ou characteristic não encontrada');
      return;
    }
    int unixTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    String payload = 'UT$unixTime';
    print('Enviando horário (silencioso): $payload');
    try {
      await rxCharacteristic!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );
      print('Horário enviado via BLE (silencioso)!');
      // Não mostra mensagem de sucesso
    } catch (e) {
      print('Erro ao enviar horário: $e');
      setState(() => isConnected = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bluetooth desconectado! Conecte novamente ao dispositivo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Adicione estes métodos para os diálogos
  Future<void> _showIntervalDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        int tempInterval = interval;
        return AlertDialog(
          title: Text('Intervalo entre sprays'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Defina o intervalo em segundos:'),
              TextField(
                controller: TextEditingController(text: interval.toString()),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    tempInterval = int.tryParse(value) ?? interval,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Confirmar'),
              onPressed: () {
                setState(() => interval = tempInterval);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDurationDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        int tempDuration = sprayDuration;
        return AlertDialog(
          title: Text('Duração do spray'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Defina a duração em segundos:'),
              TextField(
                // Substitui initialValue por controller
                controller: TextEditingController(
                  text: sprayDuration.toString(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) =>
                    tempDuration = int.tryParse(value) ?? sprayDuration,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancelar'),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Confirmar'),
              onPressed: () {
                setState(() => sprayDuration = tempDuration);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> disconnectDevice() async {
    if (device != null) {
      try {
        await device!.disconnect();
      } catch (_) {}
      device = null;
      txCharacteristic = null;
      rxCharacteristic = null;
      setState(() => isConnected = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        title: const Text(
          'Configurar Aromatizador',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: Colors.white,
            ),
            onPressed: selectDevice,
          ),
        ],
      ),
      body: Center(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Indicador removido, agora será SnackBar
                    Text(
                      'Dias de Funcionamento',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: List.generate(7, (i) {
                        final selected = weekDays[i];
                        return FilterChip(
                          label: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              diasSemana[i],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : Colors.blue.shade900,
                                fontSize: 16,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          selected: selected,
                          selectedColor: Colors.blue.shade600,
                          backgroundColor: Colors.blue.shade50,
                          checkmarkColor: Colors.white,
                          avatar: selected
                              ? Icon(Icons.check, color: Colors.white, size: 20)
                              : Icon(
                                  Icons.circle_outlined,
                                  color: Colors.blue.shade300,
                                  size: 20,
                                ),
                          elevation: selected ? 6 : 2,
                          pressElevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: selected
                                  ? Colors.blue.shade700
                                  : Colors.blue.shade200,
                              width: 2,
                            ),
                          ),
                          onSelected: (bool value) {
                            setState(() => weekDays[i] = value);
                          },
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      }),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Horários - Dias Úteis (Seg - Sex)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Horário Início'),
                            trailing: Text(startTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: startTime,
                              );
                              if (time != null) {
                                setState(() => startTime = time);
                              }
                            },
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Horário Fim'),
                            trailing: Text(endTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: endTime,
                              );
                              if (time != null) setState(() => endTime = time);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Horários - Final de Semana (Sáb - Dom)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Horário Início'),
                            trailing: Text(weekendStartTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: weekendStartTime,
                              );
                              if (time != null) {
                                setState(() => weekendStartTime = time);
                              }
                            },
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Horário Fim'),
                            trailing: Text(weekendEndTime.format(context)),
                            onTap: () async {
                              TimeOfDay? time = await showTimePicker(
                                context: context,
                                initialTime: weekendEndTime,
                              );
                              if (time != null) setState(() => weekendEndTime = time);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('Intervalo entre sprays'),
                            trailing: Text('$interval s'),
                            onTap: _showIntervalDialog,
                          ),
                          const Divider(),
                          ListTile(
                            title: const Text('Duração do spray'),
                            trailing: Text('$sprayDuration s'),
                            onTap: _showDurationDialog,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? sendConfig : null,
                        icon: const Icon(Icons.save),
                        label: const Text('Salvar Configuração'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: isConnected
                              ? Colors.blue
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isConnected ? sendCurrentTime : null,
                        icon: const Icon(Icons.access_time),
                        label: const Text('Sincronizar Horário'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: isConnected
                              ? Colors.green
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Botões de ligar/desligar spray
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: isConnected
                              ? () async {
                                  if (rxCharacteristic != null) {
                                    await rxCharacteristic!.write(
                                      utf8.encode('GET /1H'),
                                      withoutResponse: false,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              Icon(Icons.play_arrow, color: Colors.green.shade700),
                                              SizedBox(width: 10),
                                              Text('Spray LIGADO!', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          backgroundColor: Colors.green.shade100,
                                          behavior: SnackBarBehavior.floating,
                                          margin: EdgeInsets.only(top: 16, left: 16, right: 16),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                          icon: Icon(Icons.play_arrow),
                          label: Text('Ligar Spray'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: isConnected
                              ? () async {
                                  if (rxCharacteristic != null) {
                                    await rxCharacteristic!.write(
                                      utf8.encode('GET /1L'),
                                      withoutResponse: false,
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Row(
                                            children: [
                                              Icon(Icons.stop, color: Colors.red.shade700),
                                              SizedBox(width: 10),
                                              Text('Spray DESLIGADO!', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          backgroundColor: Colors.red.shade100,
                                          behavior: SnackBarBehavior.floating,
                                          margin: EdgeInsets.only(top: 16, left: 16, right: 16),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                }
                              : null,
                          icon: Icon(Icons.stop),
                          label: Text('Desligar Spray'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                          ),
                        ),
                      ],
                    ),
                    // Footer copyright como Card, igual aos outros blocos
                    const SizedBox(height: 32),
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blueGrey.shade600, Colors.blueGrey.shade800],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.business,
                                color: Colors.white,
                                size: 32,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '© 2025 ESSENCIAS E AROMY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Text(
                                'INDUSTRIA E COMERCIO DE PERFUMARIA E COSMETICOS LTDA',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  'CNPJ: 54.441.580/0001-81',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Divider(color: Colors.white24, thickness: 1),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.code,
                                    color: Colors.white60,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Desenvolvido por Leonardo Alves',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
}

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.stopScan(); // <-- Garante que não há scan antigo
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Selecione um Dispositivo')),
      body: StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        initialData: const [],
        builder: (context, snapshot) {
          final results = snapshot.data!;
          if (results.isEmpty) {
            return Center(
              child: Text(
                'Nenhum dispositivo encontrado.\nCertifique-se que o Bluetooth está ativado.',
                textAlign: TextAlign.center,
              ),
            );
          }

          final filteredResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();

          return ListView.builder(
            itemCount: filteredResults.length,
            itemBuilder: (context, index) {
              final result = filteredResults[index];
              return ListTile(
                title: Text(result.device.platformName),
                subtitle: Text(result.device.remoteId.toString()),
                onTap: _isConnecting ? null : () async {
                  if (_isConnecting) return; // Evita múltiplos cliques
                  
                  setState(() => _isConnecting = true);
                  
                  try {
                    FlutterBluePlus.stopScan();
                    final device = result.device;
                    await device.connect(timeout: Duration(seconds: 10));
                    if (mounted) {
                      Navigator.pop(context, device);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isConnecting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao conectar: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.refresh),
        onPressed: () async {
          await pedirPermissoesBluetooth(context);
          FlutterBluePlus.stopScan(); // <-- Adicione esta linha para garantir
          FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
        },
      ),
    );
  }
}

// Coloque isso fora de qualquer classe, no topo do arquivo (após os imports):
Future<void> pedirPermissoesBluetooth(BuildContext context) async {
  await [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();

  Location location = Location();
  bool serviceEnabled = await location.serviceEnabled();
  if (!serviceEnabled) {
    serviceEnabled = await location.requestService();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ative a localização para usar o Bluetooth!')),
        );
      }
      return;
    }
  }
}

// Função para mostrar diálogo de sucesso da sincronização
void _showSuccessDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 60,
        ),
        content: const Text(
          'Horário sincronizado com sucesso!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

// Função para mostrar diálogo de sucesso da configuração
void _showConfigSuccessDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 60,
        ),
        content: const Text(
          'Configuração enviada com sucesso!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
