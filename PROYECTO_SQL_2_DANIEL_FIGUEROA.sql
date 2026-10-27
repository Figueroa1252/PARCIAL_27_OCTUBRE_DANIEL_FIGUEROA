
DROP DATABASE IF EXISTS eventos_premier;
CREATE DATABASE eventos_premier;
USE eventos_premier;

-- -----------------------------------------------------
-- 1. TABLAS PRINCIPALES Y DE AUDITORÍA
-- -----------------------------------------------------

CREATE TABLE encargados (
    id_encargado INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL,
    telefono     VARCHAR(20)
);

CREATE TABLE salones (
    id_salon     INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL,
    capacidad    INT NOT NULL,
    precio_hora  DECIMAL(10,2) NOT NULL,
    estado       ENUM('Disponible', 'Ocupado', 'En mantenimiento') NOT NULL DEFAULT 'Disponible',
    id_encargado INT NOT NULL,
    FOREIGN KEY (id_encargado) REFERENCES encargados(id_encargado)
);

CREATE TABLE clientes (
    id_cliente     INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    identificacion VARCHAR(20) NOT NULL UNIQUE,
    telefono       VARCHAR(20),
    correo         VARCHAR(100),
    tipo_cliente   ENUM('Individual', 'Corporativo') NOT NULL
);

CREATE TABLE reservas (
    id_reserva   INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    id_salon     INT NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_fin    DATETIME NOT NULL,
    total_horas  DECIMAL(5,2),
    valor_total  DECIMAL(12,2),
    estado       ENUM('Confirmada', 'Cancelada', 'Finalizada') NOT NULL DEFAULT 'Confirmada',
    FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
    FOREIGN KEY (id_salon)   REFERENCES salones(id_salon),
    CHECK (fecha_fin > fecha_inicio)
);

CREATE TABLE pagos (
    id_pago       INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva    INT NOT NULL,
    fecha_pago    DATE NOT NULL,
    monto         DECIMAL(12,2) NOT NULL,
    metodo_pago   ENUM('Efectivo', 'Tarjeta', 'Transferencia') NOT NULL,
    FOREIGN KEY (id_reserva) REFERENCES reservas(id_reserva)
);

CREATE TABLE auditoria_precios (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    id_salon        INT NOT NULL,
    usuario         VARCHAR(100),
    fecha_cambio    DATETIME,
    precio_anterior DECIMAL(10,2),
    precio_nuevo    DECIMAL(10,2)
);

-- Tabla de auditoría para el módulo de pagos (Parcial)
CREATE TABLE auditoria_abonos (
    id_auditoria     INT AUTO_INCREMENT PRIMARY KEY,
    id_pago          INT NOT NULL,
    fecha_movimiento DATETIME NOT NULL,
    valor_anterior   DECIMAL(12,2),
    valor_nuevo      DECIMAL(12,2),
    usuario          VARCHAR(100)
);


-- -----------------------------------------------------
-- 2. FUNCIONES PERSONALIZADAS
-- -----------------------------------------------------

DELIMITER $$

CREATE FUNCTION calcular_total_reserva(p_precio_hora DECIMAL(10,2), p_horas DECIMAL(5,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE subtotal DECIMAL(12,2);
    DECLARE total    DECIMAL(12,2);

    SET subtotal = p_precio_hora * p_horas;
    SET total    = subtotal * 1.19; -- IVA del 19%

    RETURN total;
END$$

CREATE FUNCTION verificar_disponibilidad(p_salon_id INT, p_fecha_inicio DATETIME, p_fecha_fin DATETIME)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE cruces INT;
    DECLARE estado_salon VARCHAR(20);

    SELECT estado INTO estado_salon
    FROM salones
    WHERE id_salon = p_salon_id;

    IF estado_salon = 'En mantenimiento' THEN
        RETURN 0;
    END IF;

    SELECT COUNT(*) INTO cruces
    FROM reservas
    WHERE id_salon = p_salon_id
      AND estado <> 'Cancelada'
      AND fecha_inicio < p_fecha_fin
      AND fecha_fin > p_fecha_inicio;

    IF cruces = 0 THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END$$

-- Función solicitada en el parcial: calcular valor pendiente
CREATE FUNCTION calcular_valor_pendiente(p_total_reserva DECIMAL(12,2), p_abono DECIMAL(12,2))
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE pendiente DECIMAL(12,2);
    SET pendiente = p_total_reserva - p_abono;
    
    IF pendiente < 0 THEN
        RETURN 0;
    END IF;
    
    RETURN pendiente;
END$$

DELIMITER ;


-- -----------------------------------------------------
-- 3. TRIGGERS (DISPARADORES)
-- -----------------------------------------------------

DELIMITER $$

CREATE TRIGGER calcular_reserva_trigger
BEFORE INSERT ON reservas
FOR EACH ROW
BEGIN
    DECLARE v_precio DECIMAL(10,2);

    IF verificar_disponibilidad(NEW.id_salon, NEW.fecha_inicio, NEW.fecha_fin) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El salon no esta disponible en ese horario';
    END IF;

    SELECT precio_hora INTO v_precio
    FROM salones
    WHERE id_salon = NEW.id_salon;

    SET NEW.total_horas = CEIL(TIMESTAMPDIFF(MINUTE, NEW.fecha_inicio, NEW.fecha_fin) / 60);
    SET NEW.valor_total = calcular_total_reserva(v_precio, NEW.total_horas);
END$$

CREATE TRIGGER actualizar_estado_salon_trigger
AFTER INSERT ON reservas
FOR EACH ROW
BEGIN
    UPDATE salones
    SET estado = 'Ocupado'
    WHERE id_salon = NEW.id_salon
      AND estado = 'Disponible';
END$$

CREATE TRIGGER liberar_salon_trigger
AFTER DELETE ON reservas
FOR EACH ROW
BEGIN
    UPDATE salones
    SET estado = 'Disponible'
    WHERE id_salon = OLD.id_salon
      AND estado = 'Ocupado';
END$$

CREATE TRIGGER auditoria_precios_trigger
AFTER UPDATE ON salones
FOR EACH ROW
BEGIN
    IF OLD.precio_hora <> NEW.precio_hora THEN
        INSERT INTO auditoria_precios (id_salon, usuario, fecha_cambio, precio_anterior, precio_nuevo)
        VALUES (NEW.id_salon, CURRENT_USER(), NOW(), OLD.precio_hora, NEW.precio_hora);
    END IF;
END$$

-- Triggers de auditoría de abonos solicitados en el parcial (INSERT y UPDATE)
CREATE TRIGGER auditar_abono_insert_trigger
AFTER INSERT ON pagos
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_abonos (id_pago, fecha_movimiento, valor_anterior, valor_nuevo, usuario)
    VALUES (NEW.id_pago, NOW(), 0, NEW.monto, CURRENT_USER());
END$$

CREATE TRIGGER auditar_abono_update_trigger
AFTER UPDATE ON pagos
FOR EACH ROW
BEGIN
    IF OLD.monto <> NEW.monto THEN
        INSERT INTO auditoria_abonos (id_pago, fecha_movimiento, valor_anterior, valor_nuevo, usuario)
        VALUES (NEW.id_pago, NOW(), OLD.monto, NEW.monto, CURRENT_USER());
    END IF;
END$$

DELIMITER ;


-- -----------------------------------------------------
-- 4. DATOS DE PRUEBA
-- -----------------------------------------------------

INSERT INTO encargados (nombre, telefono) VALUES
('Laura Gomez',  '3001112233'),
('Carlos Pinto', '3004445566');

INSERT INTO salones (nombre, capacidad, precio_hora, estado, id_encargado) VALUES
('Salon Esmeralda', 50,  100000, 'Disponible', 1),
('Salon Diamante',  120, 200000, 'Disponible', 1),
('Salon Rubi',      80,  150000, 'Disponible', 2),
('Salon Zafiro',    30,   80000, 'En mantenimiento', 2),
('Salon Perla',     200, 300000, 'Disponible', 2);

INSERT INTO clientes (nombre, identificacion, telefono, correo, tipo_cliente) VALUES
('Maria Rodriguez',        '1098111222', '3101234567', 'maria@correo.com',    'Individual'),
('Constructora Andes SAS', '900123456',  '3207654321', 'info@andes.com',      'Corporativo'),
('Juan Perez',             '1098333444', '3159876543', 'juan@correo.com',     'Individual'),
('Tecnoval SAS',           '900654321',  '3112223344', 'contacto@tecnoval.co','Corporativo');

INSERT INTO reservas (id_cliente, id_salon, fecha_inicio, fecha_fin) VALUES
(2, 1, '2026-11-02 08:00:00', '2026-11-02 12:00:00'),
(2, 1, '2026-11-09 08:00:00', '2026-11-09 12:00:00'),
(2, 1, '2026-11-16 08:00:00', '2026-11-16 12:00:00'),
(2, 1, '2026-11-23 08:00:00', '2026-11-23 12:00:00'),
(1, 2, '2026-11-07 18:00:00', '2026-11-07 23:00:00'),
(3, 3, '2026-11-14 14:00:00', '2026-11-14 17:30:00'),
(4, 2, '2026-11-20 09:00:00', '2026-11-20 11:00:00');

INSERT INTO pagos (id_reserva, fecha_pago, monto, metodo_pago) VALUES
(1, '2026-10-25', 238000, 'Transferencia'),
(1, '2026-11-02', 238000, 'Tarjeta'),
(5, '2026-11-01', 500000, 'Efectivo');


-- -----------------------------------------------------
-- 5. VISTAS Y CONSULTAS DEL PARCIAL
-- -----------------------------------------------------

-- Vista general anterior
CREATE OR REPLACE VIEW vista_resumen_reservas AS
SELECT
    c.nombre        AS cliente,
    s.nombre        AS salon,
    r.fecha_inicio,
    r.fecha_fin,
    r.valor_total   AS total,
    r.estado
FROM reservas r
INNER JOIN clientes c ON r.id_cliente = c.id_cliente
INNER JOIN salones  s ON r.id_salon   = s.id_salon;

-- Vista requerida en el parcial: vista_facturacion_reservas
CREATE OR REPLACE VIEW vista_facturacion_reservas AS
SELECT 
    c.nombre AS nombre_cliente,
    r.fecha_inicio AS fecha_reserva,
    r.valor_total AS total_reserva,
    COALESCE(SUM(p.monto), 0) AS abono,
    calcular_valor_pendiente(r.valor_total, COALESCE(SUM(p.monto), 0)) AS valor_pendiente
FROM reservas r
INNER JOIN clientes c ON r.id_cliente = c.id_cliente
LEFT JOIN pagos p ON r.id_reserva = p.id_reserva
GROUP BY r.id_reserva, c.nombre, r.fecha_inicio, r.valor_total;


-- CONSULTA 1 del Parcial: Pagos pendientes (Valor pendiente mayor a 0)
SELECT 
    c.nombre AS nombre_cliente,
    r.fecha_inicio AS fecha_reserva,
    r.valor_total AS total,
    COALESCE(SUM(p.monto), 0) AS abono,
    calcular_valor_pendiente(r.valor_total, COALESCE(SUM(p.monto), 0)) AS valor_pendiente
FROM reservas r
INNER JOIN clientes c ON r.id_cliente = c.id_cliente
LEFT JOIN pagos p ON r.id_reserva = p.id_reserva
GROUP BY r.id_reserva, c.nombre, r.fecha_inicio, r.valor_total
HAVING valor_pendiente > 0;


-- CONSULTA 2 del Parcial: Top 3 clientes con más reservas pagadas completamente
SELECT 
    sub.nombre AS cliente,
    COUNT(sub.id_reserva) AS reservas_completadas
FROM (
    SELECT 
        c.id_cliente,
        c.nombre,
        r.id_reserva,
        calcular_valor_pendiente(r.valor_total, COALESCE(SUM(p.monto), 0)) AS val_pen
    FROM clientes c
    INNER JOIN reservas r ON c.id_cliente = r.id_cliente
    LEFT JOIN pagos p ON r.id_reserva = p.id_reserva
    GROUP BY c.id_cliente, c.nombre, r.id_reserva, r.valor_total
) sub
WHERE sub.val_pen = 0
GROUP BY sub.id_cliente, sub.nombre
ORDER BY reservas_completadas DESC
LIMIT 3;