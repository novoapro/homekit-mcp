import { useState } from 'react';
import { Icon } from '@/components/Icon';
import './LogDetailPanel.css';

interface LogDetailPanelProps {
  requestBody: string;
  responseBody: string;
}

export function LogDetailPanel({ requestBody, responseBody }: LogDetailPanelProps) {
  const [copiedRequest, setCopiedRequest] = useState(false);
  const [copiedResponse, setCopiedResponse] = useState(false);

  function formatJson(str: string): string {
    try {
      const parsed = JSON.parse(str);
      return JSON.stringify(parsed, null, 2);
    } catch {
      return str;
    }
  }

  function copyToClipboard(text: string, isResponse = false) {
    navigator.clipboard.writeText(text).then(() => {
      if (isResponse) {
        setCopiedResponse(true);
        setTimeout(() => setCopiedResponse(false), 1500);
      } else {
        setCopiedRequest(true);
        setTimeout(() => setCopiedRequest(false), 1500);
      }
    });
  }

  return (
    <div className="detail-panel">
      {requestBody && (
        <div className="detail-section">
          <div className="detail-header">
            <span className="detail-label">Request</span>
            <button className="copy-btn" onClick={() => copyToClipboard(requestBody)}>
              <Icon name="copy" size={12} />
              <span>{copiedRequest ? 'Copied!' : 'Copy'}</span>
            </button>
          </div>
          <pre className="detail-body">{formatJson(requestBody)}</pre>
        </div>
      )}
      {responseBody && (
        <div className="detail-section">
          <div className="detail-header">
            <span className="detail-label">Response</span>
            <button className="copy-btn" onClick={() => copyToClipboard(responseBody, true)}>
              <Icon name="copy" size={12} />
              <span>{copiedResponse ? 'Copied!' : 'Copy'}</span>
            </button>
          </div>
          <pre className="detail-body">{formatJson(responseBody)}</pre>
        </div>
      )}
    </div>
  );
}
