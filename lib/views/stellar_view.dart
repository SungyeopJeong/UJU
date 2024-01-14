// ignore_for_file: prefer_const_constructors

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:week3/const/color.dart';
import 'package:week3/const/size.dart';
import 'package:week3/enums/mode.dart';
import 'package:week3/extensions/offset.dart';
import 'package:week3/models/graph.dart';
import 'package:week3/models/node.dart';
import 'package:week3/models/edge.dart';
import 'package:week3/models/post.dart';

class StellarView extends StatefulWidget {
  const StellarView({super.key});

  @override
  State<StellarView> createState() => _StellarViewState();
}

class _StellarViewState extends State<StellarView>
    with TickerProviderStateMixin {
  Graph graph = Graph();
  Node? origin;
  Planet? tempPlanet;
  Edge? originEdge;
  Mode mode = Mode.none;
  bool isBlackholeEnabled = false;
  bool isEditing = false;

  bool get isStarSelected => selectedNode != null; // 별이 선택되었는지 여부를 추적하는 변수
  Star? selectedNode; // 선택된 노드 추적

  //텍스트 수정을 위한 선언
  bool isNoteEditing = false;
  TextEditingController titleController = TextEditingController();
  TextEditingController contentController = TextEditingController();

  // 뷰를 이동시키기 위한 Controller
  final TransformationController _transformationController =
      TransformationController();

  // 뷰를 이동시킬 때 애니메이션을 적용하기 위한 선언
  late AnimationController _animationController;
  late Animation<Matrix4> _animation;

  // 뷰의 최소 / 최대 배율, 현재 배율 저장 변수
  double _minScale = 1.0;
  double _maxScale = 4.0;
  double _currentScale = 1.0;

  final _exception = Exception('Unable to classify');

  @override
  void initState() {
    super.initState();
    // AnimationController 초기화
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _transformationController.addListener(_updateZoomSlider);

// InteractiveViewer의 초기 스케일을 기반으로 _currentScale 값을 설정합니다.
    _currentScale =
        (_transformationController.value.getMaxScaleOnAxis() - _minScale) /
            (_maxScale - _minScale);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_updateZoomSlider);
    // AnimationController 정리
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyI): () {
                setState(() {
                  mode = Mode.add;
                });
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                setState(() {
                  if (isNoteEditing) {
                    _enterViewMode();
                  } else {
                    selectedNode!.showOrbit = false;
                    selectedNode = null;
                  }
                });
              }
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  InteractiveViewer(
                    minScale: _minScale,
                    maxScale: _maxScale,
                    transformationController: _transformationController,
                    child: _buildBody(),
                  ),
                  _buildBlackhole(),
                  _buildZoomSlider(),
                ],
              ),
            ),
          ),
          _buildNoteView(),
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildBody() {
    return GestureDetector(
      onTapDown: (details) {
        if (mode == Mode.add) {
          setState(() {
            graph.addNode(
              Star(pos: details.localPosition)
                ..post = Post(
                  title: "Title Here",
                  markdownContent: "Content Here",
                )
                ..planets = []
                ..planetAnimation = AnimationController(vsync: this),
            );
            mode = Mode.none;
          });
        }
      },
      onSecondaryTap: () {
        // 마우스 오른쪽 클릭 이벤트 처리
        setState(() {
          mode = Mode.none; // 별 생성 모드 취소
        });
      },
      child: MouseRegion(
        cursor:
            mode == Mode.add ? SystemMouseCursors.precise : MouseCursor.defer,
        child: Container(
          color: MyColor.bg,
          width: double.maxFinite,
          height: double.maxFinite,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(double.maxFinite, double.maxFinite),
                painter: EdgePainter(
                  graph.edges,
                  originEdge: originEdge,
                ),
              ),
              ..._buildNodes(graph.nodes),
              if (origin != null) _buildOrigin(origin!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return GestureDetector(
      onTap: () {
        setState(() {
          mode = Mode.add;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: MyColor.surface,
          shape: BoxShape.circle,
        ),
        width: 60,
        height: 60,
        child: Icon(
          Icons.insights,
          color: MyColor.onSurface,
        ),
      ),
    );
  }

  List<Widget> _buildNodes(List<Node> nodes) {
    return nodes.skipWhile((node) => node is Planet).map((node) {
      switch (node) {
        case Star():
          return _buildStar(node);
        case Constellation():
          return _buildConstellation(node);
        default:
          throw _exception;
      }
    }).toList();
  }

  Widget _buildDeletingNode(Node node, Widget Function(Offset) childBuilder) {
    return TweenAnimationBuilder(
      tween: Tween(
        begin: node.pos,
        end: Offset(0, MediaQuery.of(context).size.height),
      ),
      duration: Duration(milliseconds: 250),
      onEnd: () {
        setState(() {
          graph.removeNode(node);
        });
      },
      builder: (_, val, __) => childBuilder(val),
    );
  }

  Widget _buildHelper(double size, List<Widget> children) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: children,
      ),
    );
  }

  Widget _buildColoredCircle(
    double size,
    Color color, {
    BoxBorder? border,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: border,
        shape: BoxShape.circle,
      ),
      width: size,
      height: size,
    );
  }

  Widget _buildPlanetCenter(Planet planet) {
    return Visibility(
      visible: planet.showPlanet,
      child: _buildColoredCircle(
        planetSize,
        planet == tempPlanet ? MyColor.star : MyColor.planet,
      ),
    );
  }

  Widget _buildPlanetArea(Planet planet) {
    return Visibility(
      visible: planet.showArea,
      child: _buildColoredCircle(
        planetAreaSize,
        planet == tempPlanet ? MyColor.starArea : MyColor.planetArea,
      ),
    );
  }

  Widget _buildEmptyPlanet(Planet planet) {
    return _buildHelper(
      planetAreaSize,
      [
        _buildPlanetArea(planet),
        _buildPlanetCenter(planet),
      ],
    );
  }

  Widget _buildPlanet(Planet planet) {
    if (planet.isDeleting) {
      return _buildDeletingNode(
        planet,
        (val) => Positioned(
          left: val.dx - planetSize / 2,
          top: val.dy - planetSize / 2,
          child: _buildPlanetCenter(planet),
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) {
        if (!isEditing) {
          setState(() {
            planet.showArea = true;
          });
        }
      },
      onExit: (_) {
        if (!isEditing) {
          setState(() {
            planet.showArea = false;
          });
        }
      },
      child: _buildEmptyPlanet(planet),
    );
  }

  Widget _buildStarCenter(Star star) {
    return Visibility(
      visible: star.showStar,
      child: _buildColoredCircle(
        starSize,
        MyColor.star.withOpacity(star == origin ? 0.2 : 1),
      ),
    );
  }

  Widget _buildStarArea(Star star) {
    return Visibility(
      visible: star.showOrbit ? true : star.showArea,
      child: _buildColoredCircle(starAreaSize, MyColor.starArea),
    );
  }

  Widget _buildStarOrbit(Star star) {
    return Visibility(
      visible: star.showOrbit,
      child: _buildHelper(
        starTotalSize,
        [
          _buildColoredCircle(
            starOrbitSize,
            MyColor.starOrbit,
            border: Border.all(color: MyColor.star),
          ),
          AnimatedBuilder(
            animation: star.planetAnimation,
            builder: (_, __) {
              final alpha = star.planetAnimation.value * 2 * pi;
              const radius = starOrbitSize / 2;
              for (final planetWithIndex in star.planets.indexed) {
                final index = planetWithIndex.$1;
                final planet = planetWithIndex.$2;
                final angle = index * 2 * pi / star.planets.length + alpha;
                final x = radius * cos(angle);
                final y = radius * sin(angle);
                planet.pos = star.pos + Offset(x, y);
              }
              return Stack(
                children: star.planets
                    .map(
                      (planet) => Positioned(
                        left: starTotalSize / 2 +
                            planet.pos.dx -
                            star.pos.dx -
                            planetAreaSize / 2,
                        top: starTotalSize / 2 +
                            planet.pos.dy -
                            star.pos.dy -
                            planetAreaSize / 2,
                        child: _buildPlanet(planet),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStar(Star star) {
    return _buildHelper(
      starTotalSize,
      [
        _buildStarOrbit(star),
        _buildStarArea(star),
        _buildStarCenter(star),
      ],
    );
  }

  void _setOnPanStart(Node node) {
    isEditing = true;
    switch (node) {
      case Planet():
        throw UnimplementedError();
      case Star():
        origin = Star(pos: node.pos)
          ..id = 0
          ..planets = []
          ..planetAnimation = AnimationController(vsync: this);
        originEdge = Edge(origin!, node);
      default:
        throw _exception;
    }
  }

  void _setOnPanEnd(Node node) {
    isEditing = false;
    switch (node) {
      case Planet():
        throw UnimplementedError();
      case Star():
        for (final other in graph.nodes + [origin!]) {
          if (other == node) continue;
          if (other == origin && mode != Mode.add) continue;
          if (other.pos.closeTo(node.pos, starOrbitSize)) {
            (other as Star).showOrbit = false;

            if (other.planets.remove(tempPlanet)) {
              other.addPlanet(Planet(star: other));
              tempPlanet = null;
            }
            if (other.planetAnimation.isAnimating) {
              other.planetAnimation.reset();
            }
            break;
          }
        }

        originEdge = null;
        origin = null;
      default:
        throw _exception;
    }
  }

  void _caseProcess(Node node) {
    switch (node) {
      case Planet():
        throw UnimplementedError();
      case Star():
        for (final other in graph.nodes + [origin!]) {
          if (other == node) continue;
          if (other == origin && mode != Mode.add) continue;
          if (other.pos.closeTo(node.pos, starOrbitSize)) {
            (other as Star).showOrbit = true;
            if (tempPlanet == null) {
              tempPlanet = Planet(star: other, showArea: true)..id = 0;
              other.planets.add(tempPlanet!);
              originEdge!.end = tempPlanet!;
            }
            if (!other.planetAnimation.isAnimating) {
              other.planetAnimation.repeat(period: Duration(seconds: 10));
            }
          } else {
            (other as Star).showOrbit = false;

            if (other.planets.remove(tempPlanet)) {
              tempPlanet = null;
              originEdge!.end = node;
            }
            if (other.planetAnimation.isAnimating) {
              other.planetAnimation.reset();
            }
          }
        }
      default:
        throw _exception;
    }
  }

  Widget _buildStar(Star star) {
    if (star.isDeleting) {
      return _buildDeletingNode(
        star,
        (val) => Positioned(
          left: val.dx - starSize / 2,
          top: val.dy - starSize / 2,
          child: _buildStarCenter(star),
        ),
      );
    }
    return Positioned(
      left: star.pos.dx - starTotalSize / 2,
      top: star.pos.dy - starTotalSize / 2,
      child: GestureDetector(
        onPanStart: (details) {
          setState(() {
            _setOnPanStart(star);
          });
        },
        onPanUpdate: (details) {
          if (star.showArea) {
            // star following cursor if area shown(interactive)
            setState(() {
              star.pos += details.delta;

              _caseProcess(star);
            });
          }
        },
        onPanEnd: (_) {
          setState(() {
            _setOnPanEnd(star);
            star.isDeleting = isBlackholeEnabled;
          });
        },
        onTap: () {
          setState(() {
            // 이전 노드의 정보를 저장합니다.
            if (isNoteEditing && selectedNode != null) {
              selectedNode!.post.title = titleController.text;
              selectedNode!.post.markdownContent = contentController.text;
            }

            // 새 노드를 선택합니다.
            if (selectedNode != star) {
              selectedNode?.showOrbit = false; // 이전 선택된 노드의 orbit을 해제합니다.
              selectedNode?.planetAnimation.reset();

              selectedNode = star; // 새로운 노드를 선택된 노드로 설정합니다.
              selectedNode!.showOrbit = true;
              selectedNode!.planetAnimation
                  .repeat(period: Duration(seconds: 10));

              // 새 노드의 정보로 텍스트 필드를 업데이트합니다.
              titleController.text = selectedNode!.post.title;
              contentController.text = selectedNode!.post.markdownContent;

              _focusOnNode(star); // 뷰포트 이동
            }
          });
        },
        child: MouseRegion(
          onHover: (details) {
            setState(() {
              // show area if mouse in area
              star.showArea = details.localPosition.closeTo(
                OffsetExt.center(starTotalSize),
                starAreaSize,
              );
            });
          },
          child: _buildEmptyStar(star),
        ),
      ),
    );
    /*GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            //원래자리에 노드 모양 위젯 생성
            origin ??= Node(node.pos)
              ..planetAnimation = AnimationController(
                vsync: this,
                upperBound: 2 * pi,
                duration: Duration(seconds: 10),
              );
            origin!.showStar = false;
            originEdge = Edge(origin!, node);
            node.showStar = true;

            void updateState(Node? other) {
              if (other == node || other == null) return;
              final distanceSquared = (other.pos - node.pos).distanceSquared;
              double radiusSquared(double diameter) => diameter * diameter / 4;
              if (distanceSquared <= radiusSquared(areaSize)) {
                final edge = Edge(origin!, other);
                if (!edges.any((element) => element == edge)) {
                  origin!.showStar = true;
                  originEdge = edge;
                  node.showStar = false;
                }
                return;
              }
              if (distanceSquared <= radiusSquared(orbitSize)) {
                other.showOrbit = true;
                if (!other.planetAnimation.isAnimating) {
                  other.planetAnimation.repeat();
                }
              } else {
                other.showOrbit = false;
                if (other.planetAnimation.isAnimating) {
                  other.planetAnimation.reset();
                }
              }
            }

            for (final other in nodes) {
              updateState(other);
            }
            if (mode == Mode.add) {
              updateState(origin);
            }
          });
        },
        onPanEnd: (details) {
          setState(() {
            for (final node in nodes) {
              node.showOrbit = false;
            }

            if (origin?.showStar ?? false) {
              node.pos = origin!.pos;
              node.showStar = true;
              originEdge!.node1 = node;
              if (!edges.contains(originEdge)) {
                edges.add(originEdge!);
              }
            }

            origin = null; // `origin`을 `null`로 설정
            originEdge = null;
          });
        },
      )*/
  }

  Widget _buildOrigin(Node node) {
    switch (node) {
      case Planet():
        return _buildEmptyPlanet(node);
      case Star():
        return Positioned(
          left: node.pos.dx - starTotalSize / 2,
          top: node.pos.dy - starTotalSize / 2,
          child: _buildEmptyStar(node),
        );
      default:
        throw _exception;
    }
  }

  Widget _buildConstellation(Constellation constellation) {
    return Placeholder();
  }

  Widget _buildBlackhole() {
    final blackholeSize =
        isBlackholeEnabled ? blackholeMaxSize : blackholeMinSize;
    return Positioned(
      left: -blackholeAreaSize / 2,
      bottom: -blackholeAreaSize / 2,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            isBlackholeEnabled = true;
          });
        },
        onExit: (_) {
          setState(() {
            isBlackholeEnabled = false;
          });
        },
        child: Container(
          width: blackholeAreaSize,
          height: blackholeAreaSize,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: MyColor.blackhole,
              shape: BoxShape.circle,
            ),
            width: blackholeSize,
            height: blackholeSize,
          ),
        ),
      ),
    );
  }

  // 줌슬라이더 만드는 함수
  Widget _buildZoomSlider() {
    return Positioned(
      left: 32,
      top: (MediaQuery.of(context).size.height - 320) / 2,
      child: Container(
        width: 48,
        height: 320,
        decoration: BoxDecoration(
          color: Color(0xFFE5E5E1),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: Offset(0, 0),
            ),
          ],
        ),
        padding: EdgeInsets.all(4),
        child: RotatedBox(
          quarterTurns: 3,
          child: _customSliderTheme(context, _customSlider(context)),
        ),
      ),
    );
  }

  // 현재 zoom 상태에 맞게 slider 값 바꾸기
  void _updateZoomSlider() {
    double scale = _transformationController.value.getMaxScaleOnAxis();
    setState(() {
      // 현재 스케일을 기반으로 슬라이더의 값을 계산합니다.
      // 계산된 값이 범위를 벗어나지 않도록 clamp 함수를 사용합니다.
      _currentScale =
          ((scale - _minScale) / (_maxScale - _minScale)).clamp(0.0, 1.0);
    });
  }

  //_customSlider의 모양 함수
  SliderTheme _customSliderTheme(BuildContext context, Widget slider) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4.0,
        thumbColor: Color(0xFF4D4D4D),
        inactiveTrackColor: Color(0xFFC5C5C5),
        activeTrackColor: Color(0xFF4D4D4D),
        overlayColor: Colors.transparent,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 10.0),
        trackShape: RoundedRectSliderTrackShape(),
      ),
      child: slider,
    );
  }

  // 슬라이더를 위치시키고 상태를 업데이트
  Widget _customSlider(BuildContext context) {
    return Slider(
      value: _currentScale,
      min: 0,
      max: 1,
      onChanged: (newValue) {
        // 슬라이더의 새 값에 따라 스케일을 계산합니다.
        double newScale = newValue * (_maxScale - _minScale) + _minScale;

        // 화면의 중앙 좌표를 계산합니다.
        final screenCenterX = MediaQuery.of(context).size.width / 2;
        final screenCenterY = MediaQuery.of(context).size.height / 2;

        // 새로운 변환 행렬을 계산합니다.
        // 화면 중앙을 기준으로 스케일을 적용합니다.
        Matrix4 newMatrix = Matrix4.identity()
          ..translate(
            -screenCenterX * (newScale - 1),
            -screenCenterY * (newScale - 1),
          )
          ..scale(newScale);

        // 변환 컨트롤러의 값을 업데이트합니다.
        _transformationController.value = newMatrix;

        // 현재 스케일 상태를 업데이트합니다.
        setState(() {
          _currentScale = newValue;
        });
      },
    );
  }

  // 주어진 노드가 화면 가로 1/4 지점에 오도록 화면을 이동시키는 함수
  void _focusOnNode(Node node) {
    // 시작 행렬
    final Matrix4 startMatrix = _transformationController.value;
    // 최종 행렬
    final Matrix4 endMatrix = Matrix4.identity()
      ..scale(3.0)
      ..translate(
        -node.pos.dx + MediaQuery.of(context).size.width / 4 / 3,
        -node.pos.dy + MediaQuery.of(context).size.height / 2 / 3,
      );

    // Tween을 사용하여 시작과 끝 행렬 사이를 보간합니다.
    _animation = Matrix4Tween(
      begin: startMatrix,
      end: endMatrix,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // 리스너를 추가하여 변환 컨트롤러의 값을 업데이트합니다.
    _animation.addListener(() {
      _transformationController.value = _animation.value;
    });

    // 애니메이션을 시작합니다.
    _animationController.forward(from: 0.0);
  }

  //선택한 별이 있는지 확인하고 선택된게 있다면 해당 Node의 Post의 title과 markdownContent를 불러와서 화면에 보여주는 위젯
  Widget _buildNoteView() {
    if (!isStarSelected) {
      return SizedBox.shrink();
    }
    return Positioned(
        top: 32,
        right: 32,
        bottom: 32,
        child: /*Focus(
          autofocus: true,
          onKey: (FocusNode node, RawKeyEvent event) {
            // ESC 키가 눌렸는지 확인합니다.
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              // 에딧모드라면 뷰모드로 전환합니다.
              if (isNoteEditing) {
                setState(() {
                  _enterViewMode();
                });
                // 이벤트 처리를 중단합니다.
                return KeyEventResult.handled;
              }
              // 에딧모드가 아니라면 노트를 닫습니다.
              setState(() {
                selectedNode!.showOrbit = false;
                selectedNode = null;
              });
              // 이벤트 처리를 중단합니다.
              return KeyEventResult.handled;
            }
            // 다른 키 이벤트는 무시합니다.
            return KeyEventResult.ignored;
          },
          child:*/
            GestureDetector(
          onTap: () {
            if (isNoteEditing) _enterViewMode();
          },
          behavior: HitTestBehavior.opaque,
          child: _buildNoteContainer(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(),
                _buildTitleSection(),
                SizedBox(height: 16),
                _buildContentSection(),
              ],
            ),
          ),
          //),
        ));
  }

  // 노트뷰에서 편집모드 -> 뷰모드로의 전환 함수
  void _enterViewMode() {
    setState(() {
      if (selectedNode != null) {
        selectedNode!.post.title = titleController.text;
        selectedNode!.post.markdownContent = contentController.text;
      }
      isNoteEditing = false;
    });
  }

  // 노트뷰에서 편집모드 -> 뷰모드로의 전환 함수
  void _enterEditMode() {
    setState(() {
      if (selectedNode != null) {
        titleController.text = selectedNode!.post.title;
        contentController.text = selectedNode!.post.markdownContent;
      }
      isNoteEditing = true;
    });
  }

  // 노트 뷰 컨테이너 위젯
  Widget _buildNoteContainer(Widget child) {
    return Container(
      width: 400, // 창의 너비를 400으로 고정
      padding: EdgeInsets.symmetric(
          horizontal: 32, vertical: 16), // 좌우 32, 위아래 16 패딩
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: child, // 내부 내용은 주어진 child 위젯으로 동적 할당
    );
  }

  // 노트뷰의 상단, 아이콘 배치 위젯
  Widget _buildHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (isNoteEditing)
          IconButton(icon: Icon(Icons.edit), onPressed: _enterViewMode),
        if (!isNoteEditing)
          IconButton(
              icon: Icon(Icons.my_library_books_rounded),
              onPressed: _enterEditMode),
        IconButton(
          icon: Icon(Icons.close),
          onPressed: () {
            setState(() {
              _enterViewMode();
              (selectedNode as Star).showOrbit = false;
              selectedNode = null;
            });
          },
        )
      ],
    );
  }

  //note_view의 타이틀 섹션 위젯, 클릭하면 editmode로 전환
  Widget _buildTitleSection() {
    return isNoteEditing
        ? _buildTitleTextField()
        : GestureDetector(
            onTap: _enterEditMode,
            child: Text(selectedNode!.post.title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)));
  }

  //note_view의 컨텐츠 섹션 위젯, 클릭하면 editmode로 전환
  Widget _buildContentSection() {
    return Expanded(
      child: isNoteEditing
          ? _buildContentTextField()
          : GestureDetector(
              onTap: _enterEditMode,
              child: MarkdownBody(
                softLineBreak: true,
                data: selectedNode!.post.markdownContent,
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context)
                      .textTheme
                      .bodyLarge!
                      .copyWith(fontSize: 16), // 폰트 크기 16으로 설정
                ),
              ),
            ),
    );
  }

  Widget _buildTitleTextField() {
    return TextField(
      controller: titleController,
      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      decoration:
          InputDecoration(hintText: 'Enter title', border: InputBorder.none),
    );
  }

  Widget _buildContentTextField() {
    return TextField(
      controller: contentController,
      style: TextStyle(fontSize: 16),
      maxLines: null,
      decoration:
          InputDecoration(hintText: 'Enter content', border: InputBorder.none),
    );
  }
}

class EdgePainter extends CustomPainter {
  final List<Edge> edges;
  final Edge? originEdge;

  EdgePainter(this.edges, {this.originEdge});

  @override
  void paint(Canvas canvas, Size size) {
    void drawLine(Edge edge) {
      final p1 = edge.start.pos;
      final p2 = edge.end.pos;
      final paint = Paint()
        ..color = MyColor.line
        ..strokeWidth = 1;
      canvas.drawLine(p1, p2, paint);
    }

    void drawDashedLine(Edge edge) {
      final p1 = edge.start.pos;
      final p2 = edge.end.pos;
      final paint = Paint()
        ..color = MyColor.dashedLine
        ..strokeWidth = 2;

      final unit = (p2 - p1) / (p2 - p1).distance;
      final dash = unit * 10;
      final gap = unit * 8;

      for (var p = p1;
          (p + dash - p1).distanceSquared <= (p2 - p1).distanceSquared;
          p += dash + gap) {
        canvas.drawLine(p, p + dash, paint);
      }
    }

    for (final edge in edges) {
      drawLine(edge);
    }
    if (originEdge != null) drawDashedLine(originEdge!);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
