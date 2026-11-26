import 'package:elets_salescall_ai/core/models/enums.dart';
import 'package:elets_salescall_ai/core/models/page_result.dart';
import 'package:elets_salescall_ai/features/calls/data/call_models.dart';
import 'package:elets_salescall_ai/features/campaigns/data/campaign_models.dart';
import 'package:elets_salescall_ai/features/leads/data/lead_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HumanCall', () {
    final json = <String, dynamic>{
      'id': '7f1c',
      'direction': 'outbound',
      'lead_id': 'lead-1',
      'lead_name': 'Priya Sharma',
      'phone_number': '98******21',
      'salesperson_id': 'u-1',
      'salesperson_name': 'Rahul Verma',
      'provider': 'exotel',
      'provider_call_id': 'ex-123',
      'status': 'not_answered',
      'started_at': '2026-11-26T09:30:00.000Z',
      'answered_at': null,
      'ended_at': '2026-11-26T09:30:40.000Z',
      'duration_seconds': 40,
      'talk_seconds': 0,
      'recording_id': null,
      'outcome': 'follow_up_required',
      'followup_at': '2026-11-27T05:30:00.000Z',
      'failure_reason': null,
      'notes': [
        {
          'id': 'n1',
          'body': 'Call back tomorrow',
          'author_id': 'u-1',
          'author_name': 'Rahul Verma',
          'created_at': '2026-11-26T09:31:00.000Z',
        },
      ],
      'created_at': '2026-11-26T09:30:00.000Z',
    };

    test('parses API fields and enums', () {
      final call = HumanCall.fromJson(json);
      expect(call.status, CallStatus.notAnswered);
      expect(call.status.isTerminal, isTrue);
      expect(call.status.isActive, isFalse);
      expect(call.outcome, CallOutcome.followUpRequired);
      expect(call.direction, CallDirection.outbound);
      expect(call.isPlacedByProvider, isTrue);
      expect(call.notes.single.authorName, 'Rahul Verma');
      expect(call.durationSeconds, 40);
      expect(call.startedAt, DateTime.utc(2026, 11, 26, 9, 30));
    });

    test('round-trips through toJson', () {
      final again = HumanCall.fromJson(HumanCall.fromJson(json).toJson());
      expect(again.toJson(), HumanCall.fromJson(json).toJson());
      expect(again.toJson()['status'], 'not_answered');
      expect(again.toJson()['outcome'], 'follow_up_required');
    });

    test('a call without provider_call_id is not treated as placed', () {
      final call = HumanCall.fromJson({...json, 'provider_call_id': null, 'status': 'failed'});
      expect(call.isPlacedByProvider, isFalse);
    });

    test('unknown status falls back instead of throwing', () {
      expect(HumanCall.fromJson({...json, 'status': 'teleported'}).status, CallStatus.unknown);
    });
  });

  group('Lead', () {
    final json = <String, dynamic>{
      'id': 'lead-1',
      'full_name': 'Priya Sharma',
      'company_name': 'Smart Cities Mission',
      'phone': '+919876543210',
      'phone_masked': '+91******3210',
      'email': 'priya@example.org',
      'designation': 'Director',
      'industry': 'Government',
      'location': 'New Delhi',
      'source': 'eGov Summit',
      'assigned_to_id': 'u-1',
      'assigned_to_name': 'Rahul Verma',
      'status': 'meeting_scheduled',
      'priority': 'high',
      'consent_status': 'granted',
      'opted_out': false,
      'is_favourite': true,
      'call_count': 3,
      'created_at': '2026-11-01T10:00:00Z',
    };

    test('parses and round-trips', () {
      final lead = Lead.fromJson(json);
      expect(lead.status, LeadStatus.meetingScheduled);
      expect(lead.priority, LeadPriority.high);
      expect(lead.consentStatus, ConsentStatus.granted);
      expect(lead.displayPhone, '+91******3210');
      expect(lead.subtitle, 'Director · Smart Cities Mission');
      final again = Lead.fromJson(lead.toJson());
      expect(again.toJson(), lead.toJson());
    });

    test('"new" status maps to LeadStatus.newLead', () {
      expect(Lead.fromJson({...json, 'status': 'new'}).status, LeadStatus.newLead);
      expect(LeadStatus.newLead.value, 'new');
    });
  });

  group('Campaign', () {
    final json = <String, dynamic>{
      'id': 'c-1',
      'name': 'eGov Summit sponsors',
      'agent_id': 'a-1',
      'agent_name': 'Elets Outreach Agent',
      'status': 'running',
      'schedule': {
        'timezone': 'Asia/Kolkata',
        'days_of_week': [1, 2, 3, 4, 5],
        'start_time': '10:00',
        'end_time': '18:00',
        'start_date': null,
        'end_date': '2026-12-31',
      },
      'max_attempts': 3,
      'retry_delay_minutes': 90,
      'max_concurrent_calls': 4,
      'calls_per_minute': 6,
      'stats': {
        'total_leads': 200,
        'pending': 50,
        'in_progress': 10,
        'attempted': 140,
        'connected': 70,
        'qualified': 12,
      },
    };

    test('parses schedule and stats', () {
      final c = Campaign.fromJson(json);
      expect(c.status, CampaignStatus.running);
      expect(c.schedule.daysOfWeek, [1, 2, 3, 4, 5]);
      expect(c.schedule.daysLabel, 'Mon, Tue, Wed, Thu, Fri');
      expect(c.stats.progress, closeTo(0.7, 1e-9));
      expect(c.retryDelayMinutes, 90);
    });

    test('round-trips through toJson', () {
      final c = Campaign.fromJson(json);
      final again = Campaign.fromJson({...c.toJson(), 'stats': json['stats']});
      expect(again.toJson(), c.toJson());
    });
  });

  test('PageResult knows when more pages exist', () {
    final page = PageResult.fromJson({
      'items': [
        {'id': '1', 'full_name': 'A', 'phone': '1'},
      ],
      'total': 41,
      'page': 2,
      'page_size': 20,
    }, Lead.fromJson);
    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(PageResult.fromJson({'items': [], 'total': 40, 'page': 2, 'page_size': 20}, Lead.fromJson).hasMore, isFalse);
  });

  test('outcome suggests the next lead status', () {
    expect(CallOutcome.converted.suggestedLeadStatus, LeadStatus.converted);
    expect(CallOutcome.notInterested.suggestedLeadStatus, LeadStatus.lost);
    expect(UserRole.fromValue('superuser'), UserRole.executive, reason: 'unknown roles get least privilege');
  });
}
