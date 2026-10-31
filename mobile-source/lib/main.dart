import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Android emulator: 10.0.2.2 points to the computer running the backend.
// For a physical phone, run with --dart-define=API_BASE_URL=http://YOUR_PC_LAN_IP:8000
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue:'http://127.0.0.1:8000',
);
const LatLng demoMapCenter = LatLng(12.9716, 77.5946); // Synthetic Bengaluru demo area.

void main() {
  runApp(const ResQRouteApp());
}

class ApiClient {
  static Future<dynamic> get(String path) async {
    final response = await http.get(Uri.parse('$apiBaseUrl$path')).timeout(
          const Duration(seconds: 12),
        );
    return _decode(response);
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('$apiBaseUrl$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final response = await http
        .patch(
          Uri.parse('$apiBaseUrl$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    return _decode(response);
  }

  static dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } on FormatException {
      body = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map<String, dynamic>
          ? (body['detail']?.toString() ?? 'Request failed (${response.statusCode}).')
          : 'Request failed (${response.statusCode}).';
      throw ApiException(message);
    }
    return body;
  }
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ResQRouteApp extends StatefulWidget {
  const ResQRouteApp({super.key});

  @override
  State<ResQRouteApp> createState() => _ResQRouteAppState();
}

class _ResQRouteAppState extends State<ResQRouteApp> {
  int _selectedIndex = 0;

  static const _titles = ['ResQRoute', 'New emergency', 'Allocation & map', 'Ambulance fleet'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardScreen(),
      const NewRequestScreen(),
      const AllocationScreen(),
      const FleetScreen(),
    ];
    return MaterialApp(
      title: 'ResQRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F75)),
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE5E7)),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: const Color(0xFFF4F7F8),
        ),
        body: SafeArea(child: pages[_selectedIndex]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.add_location_alt_outlined), selectedIcon: Icon(Icons.add_location_alt), label: 'Request'),
            NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Allocate'),
            NavigationDestination(icon: Icon(Icons.local_hospital_outlined), selectedIcon: Icon(Icons.local_hospital), label: 'Fleet'),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait([
      ApiClient.get('/dashboard/summary'),
      ApiClient.get('/requests?limit=8'),
      ApiClient.get('/ambulances'),
    ]);
    return _DashboardData(
      summary: Map<String, dynamic>.from(results[0] as Map),
      requests: _asMapList(results[1]),
      ambulances: _asMapList(results[2]),
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorPanel(
            message: snapshot.error.toString(),
            onRetry: _refresh,
          );
        }
        final data = snapshot.data!;
        final s = data.summary;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF075E59), Color(0xFF0C988A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.local_hospital, color: Colors.white, size: 34),
                    SizedBox(height: 14),
                    Text('Smarter response. Better coordination.', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 7),
                    Text('A student prototype for ambulance allocation and route comparison.', style: TextStyle(color: Colors.white70, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeading(title: 'Operations overview', subtitle: 'Pull down to refresh the demo data'),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.55,
                children: [
                  MetricCard(title: 'Ambulances', value: '${s['ambulances_total'] ?? 0}', icon: Icons.local_hospital_outlined, color: const Color(0xFF087F75)),
                  MetricCard(title: 'Available now', value: '${s['ambulances_available'] ?? 0}', icon: Icons.check_circle_outline, color: const Color(0xFF16845B)),
                  MetricCard(title: 'Open requests', value: '${s['requests_open'] ?? 0}', icon: Icons.notification_important_outlined, color: const Color(0xFFB96712)),
                  MetricCard(title: 'Completed', value: '${s['requests_completed'] ?? 0}', icon: Icons.task_alt, color: const Color(0xFF4C63BA)),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeading(title: 'Recent emergency requests', subtitle: 'Synthetic examples are created on first launch'),
              const SizedBox(height: 10),
              if (data.requests.isEmpty)
                const EmptyPanel(text: 'No requests yet. Create a request from the Request tab.')
              else
                ...data.requests.map((request) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: RequestSummaryCard(request: request),
                    )),
              const SizedBox(height: 12),
              const PrototypeNotice(),
              const SizedBox(height: 8),
              Text('API: $apiBaseUrl', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey)),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardData {
  const _DashboardData({required this.summary, required this.requests, required this.ambulances});
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> ambulances;
}

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _latController = TextEditingController(text: '12.9610');
  final _lngController = TextEditingController(text: '77.6040');
  final _descriptionController = TextEditingController(text: 'Synthetic demo request');
  String _emergencyType = 'Medical assistance';
  String _priority = 'high';
  final Set<String> _capabilities = {'basic'};
  bool _submitting = false;
  int? _createdRequestId;

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validateCoordinate(String? value, double minimum, double maximum) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed < minimum || parsed > maximum) {
      return 'Enter a valid number ($minimum to $maximum).';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _createdRequestId = null;
    });
    try {
      final result = await ApiClient.post('/requests', {
        'emergency_type': _emergencyType,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'priority': _priority,
        'pickup_lat': double.parse(_latController.text.trim()),
        'pickup_lng': double.parse(_lngController.text.trim()),
        'required_capabilities': _capabilities.toList(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _createdRequestId = (result['id'] as num).toInt());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo request #${result['id']} created. Open Allocate to compare ambulances.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create request: $error')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeading(title: 'Create a demo request', subtitle: 'Use fictional data only; this does not contact emergency services.'),
        const SizedBox(height: 14),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _emergencyType,
                decoration: const InputDecoration(labelText: 'Emergency type'),
                items: const [
                  DropdownMenuItem(value: 'Medical assistance', child: Text('Medical assistance')),
                  DropdownMenuItem(value: 'Road accident', child: Text('Road accident')),
                  DropdownMenuItem(value: 'Breathing difficulty', child: Text('Breathing difficulty')),
                  DropdownMenuItem(value: 'Cardiac emergency', child: Text('Cardiac emergency')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (value) => setState(() => _emergencyType = value ?? 'Medical assistance'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Demo priority'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'critical', child: Text('Critical')),
                ],
                onChanged: (value) => setState(() => _priority = value ?? 'high'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Demo description (optional)'),
              ),
              const SizedBox(height: 17),
              Text('Required equipment/capabilities', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  const Chip(label: Text('Basic care (required)'), avatar: Icon(Icons.check_circle, size: 18)),
                  FilterChip(
                    label: const Text('Oxygen'),
                    selected: _capabilities.contains('oxygen'),
                    onSelected: (value) => setState(() => value ? _capabilities.add('oxygen') : _capabilities.remove('oxygen')),
                  ),
                  FilterChip(
                    label: const Text('Advanced life support'),
                    selected: _capabilities.contains('advanced_life_support'),
                    onSelected: (value) => setState(() => value ? _capabilities.add('advanced_life_support') : _capabilities.remove('advanced_life_support')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeading(title: 'Pickup coordinates', subtitle: 'Default values are synthetic demo coordinates around Bengaluru.'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      validator: (value) => _validateCoordinate(value, -90, 90),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      validator: (value) => _validateCoordinate(value, -180, 180),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_location_alt),
                label: Text(_submitting ? 'Creating request...' : 'Create demo request'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
              ),
              if (_createdRequestId != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle, color: Color(0xFF16845B)),
                    title: Text('Request #$_createdRequestId created'),
                    subtitle: const Text('Go to Allocate to find and compare eligible ambulances.'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const PrototypeNotice(),
            ],
          ),
        ),
      ],
    );
  }
}

class AllocationScreen extends StatefulWidget {
  const AllocationScreen({super.key});

  @override
  State<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends State<AllocationScreen> {
  bool _loading = true;
  bool _working = false;
  String? _error;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _ambulances = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _recommendations = [];
  int? _selectedRequestId;
  int? _routeAmbulanceId;
  List<Map<String, dynamic>> _routeCoordinates = [];
  String? _routeSource;

  List<Map<String, dynamic>> get _pendingRequests => _requests.where((request) => request['status'] == 'pending').toList();

  Map<String, dynamic>? get _selectedRequest {
    for (final request in _requests) {
      if ((request['id'] as num).toInt() == _selectedRequestId) return request;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiClient.get('/requests?limit=100'),
        ApiClient.get('/ambulances'),
        ApiClient.get('/assignments?active_only=true'),
      ]);
      final requests = _asMapList(results[0]);
      final pending = requests.where((request) => request['status'] == 'pending').toList();
      final oldSelectionIsPending = pending.any((request) => (request['id'] as num).toInt() == _selectedRequestId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _ambulances = _asMapList(results[1]);
        _assignments = _asMapList(results[2]);
        if (!oldSelectionIsPending) _selectedRequestId = pending.isEmpty ? null : (pending.first['id'] as num).toInt();
        _loading = false;
        _recommendations = [];
        _routeCoordinates = [];
        _routeAmbulanceId = null;
        _routeSource = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _findRecommendations() async {
    if (_selectedRequestId == null) return;
    setState(() {
      _working = true;
      _error = null;
      _routeCoordinates = [];
    });
    try {
      final result = await ApiClient.get('/requests/$_selectedRequestId/recommendations') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _recommendations = _asMapList(result['recommendations']));
      if (_recommendations.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'No eligible available ambulance was found.')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showRoute(Map<String, dynamic> recommendation) async {
    final requestId = _selectedRequestId;
    if (requestId == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final ambulanceId = (recommendation['ambulance_id'] as num).toInt();
      final route = await ApiClient.get('/routes?request_id=$requestId&ambulance_id=$ambulanceId') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _routeAmbulanceId = ambulanceId;
        _routeCoordinates = _asMapList(route['geometry']);
        _routeSource = route['routing_source']?.toString();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _assign(Map<String, dynamic> recommendation) async {
    final requestId = _selectedRequestId;
    if (requestId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve recommendation?'),
        content: Text('Assign ${recommendation['vehicle_code']} to demo request #$requestId? This will mark the vehicle as dispatched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Review more')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve assignment')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.post('/requests/$requestId/assign', {'ambulance_id': recommendation['ambulance_id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assignment approved. You can update its progress below.')));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _updateAssignment(Map<String, dynamic> assignment, String status) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ApiClient.patch('/assignments/${assignment['id']}/status', {'status': status});
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _assignmentActions(Map<String, dynamic> assignment) {
    final status = assignment['status']?.toString() ?? '';
    String? next;
    String? label;
    if (status == 'accepted') {
      next = 'enroute';
      label = 'Mark en route';
    } else if (status == 'enroute') {
      next = 'on_scene';
      label = 'Mark on scene';
    } else if (status == 'on_scene') {
      next = 'transporting';
      label = 'Start transport';
    } else if (status == 'transporting') {
      next = 'completed';
      label = 'Complete';
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (next != null)
          FilledButton.tonal(
            onPressed: _working ? null : () => _updateAssignment(assignment, next!),
            child: Text(label!),
          ),
        TextButton(
          onPressed: _working ? null : () => _updateAssignment(assignment, 'cancelled'),
          child: const Text('Cancel assignment'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _requests.isEmpty) return ErrorPanel(message: _error!, onRetry: _loadData);
    final selected = _selectedRequest;
    final requestLatLng = selected == null
        ? null
        : LatLng((selected['pickup_lat'] as num).toDouble(), (selected['pickup_lng'] as num).toDouble());
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeading(title: 'Smart allocation', subtitle: 'Filter by availability and capabilities, then rank by road ETA.'),
          const SizedBox(height: 12),
          if (_error != null) ErrorBanner(message: _error!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pendingRequests.isEmpty)
                    const EmptyPanel(text: 'No pending requests. Create a demo request from the Request tab.')
                  else ...[
                    DropdownButtonFormField<int>(
                      initialValue: _pendingRequests.any((r) => (r['id'] as num).toInt() == _selectedRequestId) ? _selectedRequestId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Select pending request'),
                      items: _pendingRequests.map((request) {
                        final id = (request['id'] as num).toInt();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('#$id · ${request['emergency_type']} · ${_pretty(request['priority'])}', overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() {
                        _selectedRequestId = value;
                        _recommendations = [];
                        _routeCoordinates = [];
                        _routeSource = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _working || _selectedRequestId == null ? null : _findRecommendations,
                      icon: const Icon(Icons.bolt),
                      label: Text(_working ? 'Working...' : 'Find eligible ambulances'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeading(title: 'Map and route', subtitle: 'Green markers are ambulances; orange marker is the selected request.'),
          const SizedBox(height: 10),
          RouteMap(
            ambulances: _ambulances,
            requests: _requests.where((r) => r['status'] == 'pending').toList(),
            selectedRequestLocation: requestLatLng,
            routeCoordinates: _routeCoordinates,
          ),
          if (_routeSource != null) ...[
            const SizedBox(height: 8),
            Text(
              _routeSource == 'osrm_road_route'
                  ? 'Route source: OSRM road route.'
                  : 'Routing service unavailable: showing a straight-line map connector and an approximate ETA. Do not use for real dispatch.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _routeSource == 'osrm_road_route' ? Colors.blueGrey : Colors.deepOrange),
            ),
          ],
          const SizedBox(height: 18),
          const SectionHeading(title: 'Ranked recommendations', subtitle: 'Top eligible ambulance by estimated travel time is shown first.'),
          const SizedBox(height: 10),
          if (_recommendations.isEmpty)
            const EmptyPanel(text:'No eligible ambulances available for this request. Check ambulance availability and required capabilities..')
          else
            ..._recommendations.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final id = (item['ambulance_id'] as num).toInt();
              final selectedRoute = _routeAmbulanceId == id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: index == 0 ? const Color(0xFFD9F4E8) : const Color(0xFFEAF0F2), borderRadius: BorderRadius.circular(12)),
                              alignment: Alignment.center,
                              child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.w900, color: index == 0 ? const Color(0xFF126B4A) : Colors.blueGrey)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['vehicle_code']?.toString() ?? 'Ambulance $id', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                  Text(item['driver_name']?.toString() ?? '', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                ],
                              ),
                            ),
                            if (index == 0) const StatusPill(label: 'Top ETA', color: Color(0xFF167650)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _MiniMetric(icon: Icons.schedule, label: 'ETA', value: '${item['eta_minutes']} min')),
                            Expanded(child: _MiniMetric(icon: Icons.route, label: 'Distance', value: '${item['distance_km']} km')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Capabilities: ${(item['capabilities'] as List<dynamic>? ?? []).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
                        Text('Metric source: ${item['routing_source'] == 'osrm_road_route' ? 'road route' : 'approximate fallback'}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _working ? null : () => _showRoute(item),
                              icon: Icon(selectedRoute ? Icons.map : Icons.alt_route),
                              label: Text(selectedRoute ? 'Route shown' : 'View route'),
                            ),
                            FilledButton.icon(
                              onPressed: _working ? null : () => _assign(item),
                              icon: const Icon(Icons.assignment_turned_in),
                              label: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 10),
          const SectionHeading(title: 'Active assignments', subtitle: 'Update status to simulate the dispatch workflow.'),
          const SizedBox(height: 10),
          if (_assignments.isEmpty)
            const EmptyPanel(text: 'No active assignments. Approve a recommendation to try the status workflow.')
          else
            ..._assignments.map((assignment) {
              final ambulance = _ambulances.where((a) => (a['id'] as num).toInt() == (assignment['ambulance_id'] as num).toInt());
              final vehicleCode = ambulance.isEmpty ? 'Ambulance ${assignment['ambulance_id']}' : ambulance.first['vehicle_code'].toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Request #${assignment['request_id']} · $vehicleCode', style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text('Status: ${_pretty(assignment['status'])} · ETA at assignment: ${((assignment['eta_seconds'] as num).toDouble() / 60).round()} min'),
                        const SizedBox(height: 8),
                        _assignmentActions(assignment),
                      ],
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 10),
          const PrototypeNotice(),
        ],
      ),
    );
  }
}

class FleetScreen extends StatefulWidget {
  const FleetScreen({super.key});

  @override
  State<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends State<FleetScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _ambulances = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.get('/ambulances');
      if (!mounted) return;
      setState(() {
        _ambulances = _asMapList(data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setManualStatus(Map<String, dynamic> ambulance, String status) async {
    try {
      await ApiClient.patch('/ambulances/${ambulance['id']}/status', {'status': status});
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeading(title: 'Ambulance fleet', subtitle: 'Sample fleet data only. Coordinates are not live GPS positions.'),
          const SizedBox(height: 12),
          RouteMap(ambulances: _ambulances, requests: const [], height: 230),
          const SizedBox(height: 14),
          ..._ambulances.map((ambulance) {
            final status = ambulance['status']?.toString() ?? 'offline';
            final isActive = {'dispatched', 'on_scene', 'transporting'}.contains(status);
            final currentManualStatus = status == 'offline' ? 'offline' : 'available';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: const Color(0xFFE3F4F1), borderRadius: BorderRadius.circular(13)),
                            child: const Icon(Icons.local_hospital, color: Color(0xFF087F75)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ambulance['vehicle_code'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                Text(ambulance['driver_name']?.toString() ?? 'Demo driver', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                              ],
                            ),
                          ),
                          StatusPill(label: _pretty(status), color: _statusColor(status)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Capabilities: ${(ambulance['capabilities'] as List<dynamic>? ?? []).join(', ')}'),
                      Text('Location: ${(ambulance['latitude'] as num).toStringAsFixed(4)}, ${(ambulance['longitude'] as num).toStringAsFixed(4)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey)),
                      if (!isActive) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: currentManualStatus,
                          decoration: const InputDecoration(labelText: 'Manual demo availability'),
                          items: const [
                            DropdownMenuItem(value: 'available', child: Text('Available')),
                            DropdownMenuItem(value: 'offline', child: Text('Offline')),
                          ],
                          onChanged: (value) {
                            if (value != null && value != currentManualStatus) _setManualStatus(ambulance, value);
                          },
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Status changes are controlled by the active assignment workflow.', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const PrototypeNotice(),
        ],
      ),
    );
  }
}

class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.ambulances,
    required this.requests,
    this.selectedRequestLocation,
    this.routeCoordinates = const [],
    this.height = 310,
  });

  final List<Map<String, dynamic>> ambulances;
  final List<Map<String, dynamic>> requests;
  final LatLng? selectedRequestLocation;
  final List<Map<String, dynamic>> routeCoordinates;
  final double height;

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    for (final ambulance in ambulances) {
      final lat = (ambulance['latitude'] as num?)?.toDouble();
      final lng = (ambulance['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final status = ambulance['status']?.toString() ?? 'offline';
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 44,
        height: 44,
        child: Tooltip(
          message: '${ambulance['vehicle_code']} · ${_pretty(status)}',
          child: Icon(Icons.local_hospital, color: status == 'available' ? const Color(0xFF11835D) : Colors.blueGrey, size: 30),
        ),
      ));
    }
    for (final request in requests) {
      final lat = (request['pickup_lat'] as num?)?.toDouble();
      final lng = (request['pickup_lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 40,
        child: Tooltip(message: 'Request #${request['id']}', child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 30)),
      ));
    }
    if (selectedRequestLocation != null && !requests.any((request) =>
        (request['pickup_lat'] as num?)?.toDouble() == selectedRequestLocation!.latitude &&
        (request['pickup_lng'] as num?)?.toDouble() == selectedRequestLocation!.longitude)) {
      markers.add(Marker(
        point: selectedRequestLocation!,
        width: 42,
        height: 42,
        child: const Icon(Icons.emergency, color: Color(0xFFD97706), size: 32),
      ));
    }
    final routePoints = routeCoordinates.map((point) {
      return LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble());
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(initialCenter: selectedRequestLocation ?? demoMapCenter, initialZoom: 11.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.resqroute.mobile',
            ),
            if (routePoints.length >= 2)
              PolylineLayer(
                polylines: [Polyline(points: routePoints, strokeWidth: 4.5, color: const Color(0xFF087F75))],
              ),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }
}

class RequestSummaryCard extends StatelessWidget {
  const RequestSummaryCard({super.key, required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final status = request['status']?.toString() ?? 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFFFFF0DC), borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.emergency_outlined, color: Color(0xFFB96712)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${request['id']} · ${request['emergency_type']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${_pretty(request['priority'])} priority · ${_pretty(status)}', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.blueGrey.shade300),
          ],
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 23),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            Text(title, style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey, height: 1.35)),
      ],
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.blueGrey),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.blueGrey, height: 1.4))),
        ],
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 44, color: Colors.blueGrey),
            const SizedBox(height: 12),
            const Text('Cannot reach the backend', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 14),
            const Text('Start the Python API on port 8000, then check the API address shown on the Home screen.', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFE7E3), borderRadius: BorderRadius.circular(12)),
        child: Text(message, style: const TextStyle(color: Color(0xFF8B2820))),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(24)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF087F75)),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

class PrototypeNotice extends StatelessWidget {
  const PrototypeNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFE0B2))),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFF995D08)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Educational prototype only. All seeded requests and locations are synthetic. Do not use this app for real emergencies or patient-care decisions.',
              style: TextStyle(color: Color(0xFF784B0B), height: 1.35, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

String _pretty(dynamic value) {
  if (value == null) return 'Unknown';
  return value.toString().split('_').map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
}

Color _statusColor(String status) {
  switch (status) {
    case 'available':
      return const Color(0xFF16845B);
    case 'offline':
      return const Color(0xFF64748B);
    case 'dispatched':
    case 'enroute':
      return const Color(0xFFB96712);
    case 'on_scene':
    case 'transporting':
      return const Color(0xFF4C63BA);
    default:
      return const Color(0xFF64748B);
  }
}
