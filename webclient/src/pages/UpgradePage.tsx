import { useSubscription } from '@/contexts/SubscriptionContext';
import { useSetTopBar } from '@/contexts/TopBarContext';
import { Navigate } from 'react-router';
import { Icon } from '@/components/Icon';

const PRO_FEATURES = [
  {
    icon: 'play-circle-fill',
    title: 'Automation+',
    description: 'Create powerful automations with device state triggers, schedules, sunrise/sunset events, and webhook triggers.',
  },
  {
    icon: 'sparkles',
    title: 'AI Assistant',
    description: 'Generate and improve automations using natural language with Claude, OpenAI, or Gemini.',
  },
  {
    icon: 'globe',
    title: 'Web Dashboard',
    description: 'Full automation management from any browser — create, edit, and monitor automations remotely.',
  },
];

export function UpgradePage() {
  const { isPro } = useSubscription();
  useSetTopBar('Upgrade to Pro');

  if (isPro) return <Navigate to="/devices" replace />;

  return (
    <div style={{ maxWidth: 600, margin: '0 auto', padding: '40px 20px' }}>
      <div style={{ textAlign: 'center', marginBottom: 40 }}>
        <div style={{
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: 64,
          height: 64,
          borderRadius: 16,
          backgroundColor: 'rgba(255, 204, 0, 0.15)',
          marginBottom: 16,
        }}>
          <Icon name="crown-fill" size={32} style={{ color: '#FFCC00' }} />
        </div>
        <h1 style={{ fontSize: 28, fontWeight: 700, color: 'var(--text-primary)', margin: '0 0 8px' }}>
          CompAI - Home Pro
        </h1>
        <p style={{ fontSize: 16, color: 'var(--text-secondary)', margin: 0 }}>
          Unlock the full potential of your smart home
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, marginBottom: 40 }}>
        {PRO_FEATURES.map((feature) => (
          <div
            key={feature.title}
            style={{
              display: 'flex',
              gap: 16,
              padding: 20,
              borderRadius: 12,
              backgroundColor: 'var(--surface-primary)',
              border: '1px solid var(--border-primary)',
            }}
          >
            <div style={{
              flexShrink: 0,
              width: 40,
              height: 40,
              borderRadius: 10,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: 'rgba(255, 204, 0, 0.1)',
            }}>
              <Icon name={feature.icon} size={20} style={{ color: '#FFCC00' }} />
            </div>
            <div>
              <h3 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: '0 0 4px' }}>
                {feature.title}
              </h3>
              <p style={{ fontSize: 14, color: 'var(--text-secondary)', margin: 0, lineHeight: 1.5 }}>
                {feature.description}
              </p>
            </div>
          </div>
        ))}
      </div>

      <div style={{
        textAlign: 'center',
        padding: 24,
        borderRadius: 12,
        backgroundColor: 'var(--surface-primary)',
        border: '1px solid var(--border-primary)',
      }}>
        <Icon name="laptop" size={24} style={{ color: 'var(--text-secondary)', marginBottom: 12 }} />
        <h3 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: '0 0 8px' }}>
          Subscribe in the macOS app
        </h3>
        <p style={{ fontSize: 14, color: 'var(--text-secondary)', margin: 0, lineHeight: 1.5 }}>
          Open <strong>CompAI - Home</strong> on your Mac, then go to<br />
          <strong>Settings &rarr; Subscription</strong> to subscribe.
        </p>
      </div>
    </div>
  );
}
