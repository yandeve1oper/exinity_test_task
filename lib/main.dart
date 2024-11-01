import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

void main() => runApp(const TradingApp());

class TradingApp extends StatefulWidget {
  const TradingApp({super.key});

  @override
  State<TradingApp> createState() => _TradingAppState();
}

class _TradingAppState extends State<TradingApp> {
  // Integrated WebSockets for Real-Time Data Updates
  final WebSocketChannel _channel = WebSocketChannel.connect(
    Uri.parse('wss://api.exinity.com/marketdata/socket'),
  );
  List<dynamic> _marketData = [];
  bool _isLoading = true;

  // Used `RetryClient` with Timeout for Data Fetching
  final http.Client _client = RetryClient(
    http.Client(),
    retries: 3,
    when: (response) =>
        response.statusCode >= 500 || response.statusCode == 408,
    onRetry: (request, response, retryCount) {
      if (kDebugMode) {
        print('Retrying request: Attempt #$retryCount');
      }
    },
  );

  @override
  void initState() {
    super.initState();
    _initializeWebSocket();
  }

  void _initializeWebSocket() {
    _channel.stream.listen((data) {
      // Prevented State Updates on Inactive Widgets
      if (mounted) {
        setState(() {
          _marketData = parseMarketData(data);
          _isLoading = false;
        });
      }
    }, onError: (error) {
      if (kDebugMode) {
        print('WebSocket error: $error');
      }

      _showErrorSnackBar();
    }, onDone: () {
      if (kDebugMode) {
        print('WebSocket closed');
      }
    });
  }

  Future<void> _fetchMarketData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .get(Uri.parse('https://api.exinity.com/marketdata'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        setState(() {
          _marketData = json.decode(response.body);
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load market data');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching market data: $error');
      }

      _showErrorSnackBar();
      setState(() => _isLoading = false);
    }
  }

  // Improved Error Handling and User Notifications
  void _showErrorSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Failed to load data. Try again.'),
        action: SnackBarAction(label: 'Retry', onPressed: _fetchMarketData),
      ),
    );
  }

  List<dynamic> parseMarketData(String data) {
    try {
      return json.decode(data);
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing data: $e');
      }

      return [];
    }
  }

  @override
  void dispose() {
    _client.close();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exinity Trading')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          // Added Pull-to-Refresh for Manual Data Refresh
          : RefreshIndicator(
              onRefresh: _fetchMarketData,
              child: ListView.builder(
                itemCount: _marketData.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(_marketData[index]['symbol']),
                    subtitle: Text(_marketData[index]['price'].toString()),
                  );
                },
              ),
            ),
    );
  }
}
