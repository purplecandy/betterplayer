// Dart imports:
import 'dart:async';

// Project imports:
import 'package:better_player/better_player.dart';
import 'package:better_player/src/core/better_player_with_controls.dart';
// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
// Package imports:
import 'package:visibility_detector/visibility_detector.dart';
import 'package:wakelock/wakelock.dart';

import 'better_player_controller_provider.dart';

typedef BetterPlayerRoutePageBuilder = Widget Function(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    BetterPlayerControllerProvider controllerProvider);

class BetterPlayer extends StatefulWidget {
  const BetterPlayer(
      {Key key,
      @required this.controller,
      @required this.playerLanguage = PlayerLanguage.en})
      : assert(
            controller != null, 'You must provide a better player controller'),
        super(key: key);

  factory BetterPlayer.network(
    String url, {
    BetterPlayerConfiguration betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource:
              BetterPlayerDataSource(BetterPlayerDataSourceType.network, url),
        ),
      );

  factory BetterPlayer.file(
    String url, {
    BetterPlayerConfiguration betterPlayerConfiguration,
  }) =>
      BetterPlayer(
        controller: BetterPlayerController(
          betterPlayerConfiguration ?? const BetterPlayerConfiguration(),
          betterPlayerDataSource:
              BetterPlayerDataSource(BetterPlayerDataSourceType.file, url),
        ),
      );

  ///*variables
  final BetterPlayerController controller;
  final PlayerLanguage playerLanguage;
  @override
  BetterPlayerState createState() {
    return BetterPlayerState();
  }
}

class BetterPlayerState extends State<BetterPlayer>
    with WidgetsBindingObserver {
  BetterPlayerConfiguration get _betterPlayerConfiguration =>
      widget.controller.betterPlayerConfiguration;

  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(Duration.zero, () {
      _setup();
    });
  }

  Future<void> _setup() async {
    widget.controller.addListener(onFullScreenChanged);
    var locale = const Locale("en", "US");
    if (mounted) {
      final contextLocale = Localizations.localeOf(context);
      if (contextLocale != null) {
        locale = contextLocale;
      }
    }
    widget.controller.setupTranslations(widget.playerLanguage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(onFullScreenChanged);

    ///Controller from list widget must be dismissed manually
    if (widget.controller.betterPlayerPlaylistConfiguration == null) {
      widget.controller.dispose();
    }

    super.dispose();
  }

  @override
  void didUpdateWidget(BetterPlayer oldWidget) {
    if (oldWidget.controller != widget.controller) {
      widget.controller.addListener(onFullScreenChanged);
    }
    super.didUpdateWidget(oldWidget);
  }

  // ignore: avoid_void_async
  Future<void> onFullScreenChanged() async {
    final controller = widget.controller;
    if (controller.isFullScreen && !_isFullScreen) {
      _isFullScreen = true;
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen && !controller.cancelFullScreenDismiss) {
      Navigator.of(context, rootNavigator: true).pop();
      _isFullScreen = false;
    }

    if (controller.cancelFullScreenDismiss) {
      controller.cancelFullScreenDismiss = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BetterPlayerControllerProvider(
      controller: widget.controller,
      child: _buildPlayer(),
    );
  }

  Widget _buildFullScreenVideo(
      BuildContext context,
      Animation<double> animation,
      BetterPlayerControllerProvider controllerProvider) {
    return Scaffold(
      resizeToAvoidBottomPadding: false,
      body: Container(
        alignment: Alignment.center,
        color: Colors.black,
        child: controllerProvider,
      ),
    );
  }

  AnimatedWidget _defaultRoutePageBuilder(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      BetterPlayerControllerProvider controllerProvider) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = BetterPlayerControllerProvider(
        controller: widget.controller, child: _buildPlayer());

    final routePageBuilder = _betterPlayerConfiguration.routePageBuilder;
    if (routePageBuilder == null) {
      return _defaultRoutePageBuilder(
          context, animation, secondaryAnimation, controllerProvider);
    }

    return routePageBuilder(
        context, animation, secondaryAnimation, controllerProvider);
  }

  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final TransitionRoute<void> route = PageRouteBuilder<void>(
      settings: const RouteSettings(),
      pageBuilder: _fullScreenRoutePageBuilder,
    );

    await SystemChrome.setEnabledSystemUIOverlays([]);

    if (isAndroid) {
      if (_betterPlayerConfiguration.autoDetectFullscreenDeviceOrientation ==
          true) {
        final aspectRatio =
            widget?.controller?.videoPlayerController?.value?.aspectRatio ??
                1.0;
        List<DeviceOrientation> deviceOrientations;
        if (aspectRatio < 1.0) {
          deviceOrientations = [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown
          ];
        } else {
          deviceOrientations = [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight
          ];
        }
        await SystemChrome.setPreferredOrientations(deviceOrientations);
      } else {
        await SystemChrome.setPreferredOrientations(
          widget.controller.betterPlayerConfiguration
              .deviceOrientationsOnFullScreen,
        );
      }
    } else {
      await SystemChrome.setPreferredOrientations(
        widget.controller.betterPlayerConfiguration
            .deviceOrientationsOnFullScreen,
      );
    }

    if (!_betterPlayerConfiguration.allowedScreenSleep) {
      Wakelock.enable();
    }

    await Navigator.of(context, rootNavigator: true).push(route);
    _isFullScreen = false;
    widget.controller.exitFullScreen();

    // The wakelock plugins checks whether it needs to perform an action internally,
    // so we do not need to check Wakelock.isEnabled.
    Wakelock.disable();

    await SystemChrome.setEnabledSystemUIOverlays(
        _betterPlayerConfiguration.systemOverlaysAfterFullScreen);
    await SystemChrome.setPreferredOrientations(
        _betterPlayerConfiguration.deviceOrientationsAfterFullScreen);
  }

  Widget _buildPlayer() {
    return VisibilityDetector(
      key: Key("${widget.controller.hashCode}_key"),
      onVisibilityChanged: (VisibilityInfo info) =>
          widget.controller.onPlayerVisibilityChanged(info.visibleFraction),
      child: BetterPlayerWithControls(
        controller: widget.controller,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    widget.controller.setAppLifecycleState(state);
  }
}
