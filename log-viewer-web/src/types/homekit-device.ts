export interface RESTValidValue {
  value: unknown;
  description?: string;
}

export interface RESTCharacteristic {
  id: string;
  name: string;
  type: string;
  value?: unknown;
  format: string;
  units?: string;
  permissions: string[];
  minValue?: number;
  maxValue?: number;
  stepValue?: number;
  validValues?: RESTValidValue[];
}

export interface RESTService {
  id: string;
  name: string;
  type: string;
  characteristics: RESTCharacteristic[];
}

export interface RESTDevice {
  id: string;
  name: string;
  room?: string;
  isReachable: boolean;
  services: RESTService[];
}

export interface RESTScene {
  id: string;
  name: string;
  type: string;
  isExecuting: boolean;
  actionCount: number;
}
