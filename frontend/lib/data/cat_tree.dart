// CAT1 → CAT2 → [CAT3] taxonomy used for cascading filters and dashboard drill-down.
// Keys and values are lowercase; compare with .toLowerCase().trim().
const catTree = <String, Map<String, List<String>>>{
  'servicios': {
    'outsourcing it': ['asistencia técnica', 'servicios gestionados', 'integración/migración de sistemas', 'servicios de ciberseguridad - soc', 'oficina técnica'],
    'mantenimiento': ['soporte', 'mantenimiento sistemas/hardware', 'helpdesk', 'proyectos de monitorización'],
    'servicios cloud': ['saas', 'iaas', 'otros servicios cloud', 'paas'],
    'consultoría': ['seguridad/rgpd', 'it/tecnología', 'negocio', 'calidad'],
  },
  'hardware': {
    'almacenamiento': ['almacenamiento high end', 'almacenamiento modular', 'switches san'],
    'audiovisuales': ['sistemas audiovisuales', 'proyectos de aulas digitales', 'kioscos de información', 'videoconferencia'],
    'backup hardware': ['appliances'],
    'ciberseguridad': ['firewalls', 'seguridad perimetral', 'otros ciberseguridad'],
    'infraestructura cpd': ['cpd', 'sais', 'cableado'],
    'microinformática': ['pcs', 'impresoras/multifuncionales/scanner', 'portátiles', 'componentes', 'consumibles', 'terminales ligeros', 'tablets', 'dispositivos apple'],
    'seguridad': ['sistemas de control'],
    'servidores': ['servidores high end', 'hiperconvergencia (edge computing)', 'servidores hpc', 'servidores departamentales'],
    'telecomunicaciones': ['electrónica de red', 'internet de las cosas (iot)', 'wifi', 'balanceadores'],
  },
  'software': {
    'software específico': ['aplicaciones específicas', 'desarrollo de software', 'elearning', 'streaming', 'redes sociales'],
    'software de gestión': ['erp', 'otros software de gestión', 'backup software'],
    'software de infraestructura': ['otros software', 'mantenimiento aplicaciones'],
    'software de seguridad': ['otros software de seguridad'],
    'software de inteligencia artificial': ['inteligencia artificial (ia)'],
    'formación': ['formación'],
    'smart cities': ['smart cities'],
    'sistemas autónomos': ['sistemas autónomos'],
  },
  'otros': {
    'otros': ['solar', 'otros servicios de telecomunicaciones móviles'],
  },
};
