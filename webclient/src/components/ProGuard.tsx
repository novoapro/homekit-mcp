import { useSubscription } from '@/contexts/SubscriptionContext';
import { Icon } from './Icon';
import { Link } from 'react-router';

interface ProGuardProps {
  feature: string;
  description: string;
  children: React.ReactNode;
}

export function ProGuard({ feature, description, children }: ProGuardProps) {
  const { isPro, loading } = useSubscription();

  if (loading) return <>{children}</>;
  if (isPro) return <>{children}</>;

  return (
    <div className="pro-guard-overlay">
      {children}
      <div className="pro-guard-banner">
        <div className="pro-guard-content">
          <div className="pro-guard-icon">
            <Icon name="crown-fill" size={32} />
          </div>
          <h3 className="pro-guard-title">{feature} requires Pro</h3>
          <p className="pro-guard-description">{description}</p>
          <Link to="/upgrade" className="pro-guard-button">
            <Icon name="crown-fill" size={16} />
            <span>Upgrade to Pro</span>
          </Link>
        </div>
      </div>
    </div>
  );
}
