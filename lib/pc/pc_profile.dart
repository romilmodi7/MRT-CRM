import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/stickers.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../core/widgets.dart';
import 'pc_models.dart';
import 'room_media_screen.dart';

/// Round profile picture of the private chat: the photo the person chose, or the coloured initial when there is none.
/// [tag] changes whenever the photo changes ('' = no photo), so a new photo is loaded and an old one is never shown.
class PcAvatar extends StatelessWidget {
  final String name;
  final String tag;
  final bool mine;
  final double size;
  const PcAvatar({super.key, required this.name, required this.tag, this.mine = false, this.size = 40});

  static String key(String tag, bool mine) => 'pcph${mine ? 'm' : 'p'}${PcApi.roomId}$tag';

  @override
  Widget build(BuildContext context) {
    if (tag.isEmpty) return Avatar(name, size: size);
    return ClipOval(
      child: AuthImage(key: ValueKey(key(tag, mine)), cacheKey: key(tag, mine), loader: () => PcApi.bytes(PcApi.room('x/photo/${mine ? 'me' : 'peer'}')), width: size, height: size),
    );
  }
}

/// "Contact info" of the private chat (opens when the name at the top of the chat is tapped):
/// big photo, name, online / last seen, call buttons, media, starred messages and your own profile photo.
class PcProfileScreen extends StatefulWidget {
  final String name;
  final ValueNotifier<String> status;     // "online", "last seen ...", kept fresh by the chat
  final String peerTag;
  final String myTag;
  final String myName;
  final int starCount;
  final bool canCall;
  final void Function(bool video) onCall;
  final void Function(String myTag) onMyPhoto;
  const PcProfileScreen({super.key, required this.name, required this.status, required this.peerTag, required this.myTag, required this.myName, required this.starCount, required this.canCall, required this.onCall, required this.onMyPhoto});

  @override
  State<PcProfileScreen> createState() => _PcProfileScreenState();
}

class _PcProfileScreenState extends State<PcProfileScreen> {
  late String _myTag = widget.myTag;
  bool _busy = false;

  Future<void> _changePhoto() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 10),
          ListTile(leading: Icon(Icons.photo_library_rounded, color: C.accent2), title: Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: Icon(Icons.photo_camera_rounded, color: C.accent2), title: Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
          if (_myTag.isNotEmpty) ListTile(leading: Icon(Icons.delete_outline_rounded, color: C.danger), title: Text('Remove photo', style: TextStyle(color: C.danger)), onTap: () => Navigator.pop(context, 'remove')),
          SizedBox(height: 8),
        ]),
      ),
    );
    if (pick == null || !mounted) return;
    setState(() => _busy = true);
    try {
      ApiRes r;
      if (pick == 'remove') {
        r = await PcApi.post(PcApi.room('x/photo/remove'));
      } else {
        final x = await AwayGuard.run(() => ImagePicker().pickImage(source: pick == 'camera' ? ImageSource.camera : ImageSource.gallery, maxWidth: 1080, maxHeight: 1080, imageQuality: 86));
        if (x == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        r = await PcApi.upload(PcApi.room('x/photo'), {}, [File(x.path)]);
      }
      if (!mounted) return;
      if (r.ok && r.data is Map) {
        setState(() => _myTag = ((r.data as Map)['tag'] ?? '').toString());
        widget.onMyPhoto(_myTag);
        toast(context, pick == 'remove' ? 'Photo removed' : 'Profile photo updated');
      } else {
        toast(context, r.msg);
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not change the photo.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _tile(IconData icon, String title, {String? trailing, VoidCallback? onTap, Color? color}) => Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: color ?? C.accent2),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          trailing: trailing == null ? Icon(Icons.chevron_right_rounded, color: C.hint) : Row(mainAxisSize: MainAxisSize.min, children: [Text(trailing, style: TextStyle(color: C.muted)), Icon(Icons.chevron_right_rounded, color: C.hint)]),
        ),
      );

  Widget _act(IconData icon, String label, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? .4 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: C.g2, border: Border.all(color: C.line)), child: Icon(icon, color: C.accent2, size: 26)),
            SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12.5, color: C.muted, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        appBar: AppBar(title: Text('Contact info')),
        body: ListView(padding: EdgeInsets.fromLTRB(0, 8, 0, 24), children: [
          Center(
            child: GestureDetector(
              onTap: widget.peerTag.isEmpty
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImageViewerPage(cacheKey: '${PcAvatar.key(widget.peerTag, false)}full', loader: () => PcApi.bytes(PcApi.room('x/photo/peer')), title: widget.name))),
              child: PcAvatar(name: widget.name, tag: widget.peerTag, size: 132),
            ),
          ),
          SizedBox(height: 14),
          Center(child: Text(widget.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          SizedBox(height: 4),
          Center(
            child: ValueListenableBuilder<String>(
              valueListenable: widget.status,
              builder: (_, s, __) => Text(s.isEmpty ? 'Private chat' : s, style: TextStyle(fontSize: 14, color: s == 'online' || s == 'typing...' ? C.success : C.muted)),
            ),
          ),
          SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _act(Icons.call_rounded, 'Voice', widget.canCall ? () { Navigator.pop(context); widget.onCall(false); } : null),
            SizedBox(width: 26),
            _act(Icons.videocam_rounded, 'Video', widget.canCall ? () { Navigator.pop(context); widget.onCall(true); } : null),
            SizedBox(width: 26),
            _act(Icons.search_rounded, 'Search', () => Navigator.pop(context, {'do': 'search'})),
          ]),
          SizedBox(height: 18),
          Divider(color: C.line, height: 1),
          _tile(Icons.perm_media_rounded, 'Media, links and docs', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomMediaScreen(title: widget.name)))),
          _tile(Icons.star_rounded, 'Starred messages', trailing: '${widget.starCount}', onTap: () async {
            final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => PcStarredScreen()));
            if (id != null && context.mounted) Navigator.pop(context, {'do': 'jump', 'id': id});
          }),
          Divider(color: C.line, height: 1),
          Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 6), child: Text('YOUR PROFILE', style: TextStyle(fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: C.muted))),
          ListTile(
            leading: Stack(children: [
              PcAvatar(name: widget.myName, tag: _myTag, mine: true, size: 52),
              if (_busy) Positioned.fill(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x88000000)), child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))),
            ]),
            title: Text(widget.myName.isEmpty ? 'You' : widget.myName, style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_myTag.isEmpty ? 'No profile photo. The other person sees your initial.' : 'This photo is shown to the other person.', style: TextStyle(fontSize: 12.5, color: C.muted)),
            trailing: TextButton(onPressed: _busy ? null : _changePhoto, child: Text(_myTag.isEmpty ? 'Set photo' : 'Change')),
          ),
        ]),
      ),
    );
  }
}

/// Starred messages of this private room. Tapping one goes back to the chat at that message.
class PcStarredScreen extends StatefulWidget {
  const PcStarredScreen({super.key});
  @override
  State<PcStarredScreen> createState() => _PcStarredScreenState();
}

class _PcStarredScreenState extends State<PcStarredScreen> {
  List<PcMsg> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    PcApi.get(PcApi.room('x/stars')).then((r) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (r.ok && r.data is Map) _items = (((r.data as Map)['items'] as List?) ?? []).whereType<Map>().map(PcMsg.from).toList();
      });
    });
  }

  String _text(PcMsg m) {
    final st = m.type == 'text' ? StickerMsg.parse(m.body) : null;
    if (st != null) return st.isImage ? 'Sticker${st.cap.isEmpty ? '' : ' · ${st.cap}'}' : '${st.e} ${st.cap}'.trim();
    if ((m.body ?? '').isNotEmpty && (m.type == 'text' || m.isMedia)) return m.body!;
    return switch (m.type) { 'image' => 'Photo', 'video' => 'Video', 'audio' => 'Voice message', 'file' => m.mediaName.isEmpty ? 'File' : m.mediaName, 'gif' => 'GIF', 'location' => 'Location', 'contact' => 'Contact', 'sticker' => 'Sticker', _ => 'Message' };
  }

  IconData _icon(PcMsg m) => switch (m.type) { 'image' => Icons.image_rounded, 'video' => Icons.videocam_rounded, 'audio' => Icons.mic_rounded, 'file' => Icons.insert_drive_file_rounded, 'location' => Icons.location_on_rounded, 'contact' => Icons.person_rounded, _ => Icons.star_rounded };

  @override
  Widget build(BuildContext context) {
    return Aurora(
      child: Scaffold(
        appBar: AppBar(title: Text('Starred messages')),
        body: _loading
            ? Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? EmptyState(icon: Icons.star_border_rounded, title: 'No starred messages', sub: 'Hold a message and tap Star to keep it here')
                : ListView.separated(
                    padding: EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final m = _items[i];
                      return Material(
                        color: C.g1,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, m.id),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(_icon(m), color: Color(0xFFF5B400), size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m.mine ? 'You' : 'Them', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.accent2)),
                                  SizedBox(height: 2),
                                  Text(_text(m), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, height: 1.35)),
                                  SizedBox(height: 4),
                                  Text(m.ts > 0 ? '${dayLabel(m.ts)} · ${clock(m.ts)}' : '', style: TextStyle(fontSize: 11.5, color: C.muted)),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
