import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as imglib;
import 'package:rxdart/rxdart.dart';

typedef convert_func = Pointer<Uint32> Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32, Int32, Int32);
typedef Convert = Pointer<Uint32> Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int, int, int, int);

class ColorPickerWidget extends StatefulWidget {
  ColorPickerWidget(this.cameras);

  final List<CameraDescription> cameras;

  @override
  _ColorPickerWidgetState createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  GlobalKey imageKey = GlobalKey();

  final BehaviorSubject<Color> _stateController = BehaviorSubject<Color>();
  final BehaviorSubject<CameraImage> _cameraStream = BehaviorSubject<CameraImage>();
  final BehaviorSubject<imglib.Image> _screenshotStream = BehaviorSubject<imglib.Image>();

  CameraController camera;

  Convert conv;
  Offset cameraSize;

  final DynamicLibrary convertImageLib = Platform.isAndroid
      ? DynamicLibrary.open("libconvertImage.so")
      : DynamicLibrary.process();

  @override
  void initState() {
    super.initState();
  
    camera = CameraController(widget.cameras[0], ResolutionPreset.medium, enableAudio: false);
    camera.initialize().then((_) {
      if (!mounted) return;

      camera.startImageStream((image) => _cameraStream.add(image));

      setState(() {});
    });

    _cameraStream.listen((CameraImage value) => captureImage(value));
    
    _screenshotStream.listen((imglib.Image value) async => loadSnapshotBytes());

    conv = convertImageLib.lookup<NativeFunction<convert_func>>('convertImage').asFunction<Convert>();
  }

  @override
  void dispose() {
    camera.stopImageStream();
    camera?.dispose();
    _cameraStream.close();
    _stateController.close();
    _screenshotStream.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    cameraSize = Offset(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height * 0.7);

    return Scaffold(
        appBar: AppBar(),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: cameraSize.dy,
              width: MediaQuery.of(context).size.width,
              child: Stack(
                children: <Widget>[
                  GestureDetector(
                      onPanDown: (details) {
                        searchPixel();
                      },
                      onPanUpdate: (details) {
                        searchPixel();
                      },
                      child: Container(
                          height: cameraSize.dy,
                          width: cameraSize.dx,
                          child: CameraPreview(camera))),
                  Center(
                    child: Container(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(width: 2.0, color: Colors.white),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2))
                                ]),
                            child: Container(
                              margin: EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  StreamBuilder(
                      initialData: Colors.green[500],
                      stream: _stateController.stream,
                      builder: (buildContext, snapColor) {
                        Color selectedColor = snapColor.data ?? Colors.green;
                        return IgnorePointer(
                          ignoring: true,
                          child: Stack(
                            children: <Widget>[
                              Center(
                                child: Container(
                                  width: 110,
                                  height: 20,
                                  margin: EdgeInsets.only(top: 160),
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(50),
                                      border: Border.all(
                                          width: 1.0, color: Colors.white),
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black12,
                                            blurRadius: 4,
                                            offset: Offset(0, 2))
                                      ]),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: <Widget>[
                                      AnimatedContainer(
                                        duration: Duration(milliseconds: 500),
                                        width: 15,
                                        height: 15,
                                        margin: EdgeInsets.only(left: 2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: selectedColor,
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          margin: EdgeInsets.only(right: 5),
                                          child: Text(
                                            "$selectedColor",
                                            style: TextStyle(fontSize: 10),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: Colors.white,
              ),
            )
          ],
        ));
  }

  Future<void> searchPixel() async {
    captureImage(_cameraStream.stream.value).then((value) => loadSnapshotBytes());
  }

  Future<void> loadSnapshotBytes() async {
    int abgrToArgb(int argbColor) {
      int r = (argbColor >> 16) & 0xFF;
      int b = argbColor & 0xFF;
      return (argbColor & 0xFF00FF00) | (b << 16) | r;
    }

    double px = _screenshotStream.value.width / 2;
    double py = _screenshotStream.value.height / 2;

    int pixel32 = _screenshotStream.value.getPixelSafe(px.toInt(), py.toInt() - 20);
    int hex = abgrToArgb(pixel32);

    _stateController.add(Color(hex));
  }

  Future<void> captureImage(CameraImage image) async {
    imglib.Image img;

    if (Platform.isAndroid) {
      // Allocate memory for the 3 planes of the image
      Pointer<Uint8> p = allocate(count: image.planes[0].bytes.length);
      Pointer<Uint8> p1 = allocate(count: image.planes[1].bytes.length);
      Pointer<Uint8> p2 = allocate(count: image.planes[2].bytes.length);

      // Assign the planes data to the pointers of the image
      Uint8List pointerList = p.asTypedList(image.planes[0].bytes.length);
      Uint8List pointerList1 = p1.asTypedList(image.planes[1].bytes.length);
      Uint8List pointerList2 = p2.asTypedList(image.planes[2].bytes.length);
      pointerList.setRange(0, image.planes[0].bytes.length, image.planes[0].bytes);
      pointerList1.setRange(0, image.planes[1].bytes.length, image.planes[1].bytes);
      pointerList2.setRange(0, image.planes[2].bytes.length, image.planes[2].bytes);

      // Call the convertImage function and convert the YUV to RGB
      Pointer<Uint32> imgP = conv(
          p,
          p1,
          p2,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel,
          image.planes[0].bytesPerRow,
          image.height);

      // Get the pointer of the data returned from the function to a List
      List imgData = imgP.asTypedList((image.planes[0].bytesPerRow * image.height));
      // Generate image from the converted data
      img = imglib.Image.fromBytes(image.height, image.planes[0].bytesPerRow, imgData);

      // Free the memory space allocated
      // from the planes and the converted data
      free(p);
      free(p1);
      free(p2);
      free(imgP);
    } else if (Platform.isIOS) {
      img = imglib.Image.fromBytes(
        image.planes[0].bytesPerRow,
        image.height,
        image.planes[0].bytes,
        format: imglib.Format.bgra,
      );
    }

    _screenshotStream.add(img);
  }
}
