resource "aws_lb" "gitlab_ssh" {
  name               = "${var.project_name}-nlb"
  load_balancer_type = "network"
  internal           = false
  security_groups    = [aws_security_group.nlb.id]
  subnets            = var.public_subnet_ids
}

resource "aws_lb_target_group" "gitlab_ssh" {
  name        = "${var.project_name}-ssh-tg"
  port        = 22
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
  }
}

resource "aws_lb_listener" "gitlab_ssh" {
  load_balancer_arn = aws_lb.gitlab_ssh.arn
  port              = 22
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_ssh.arn
  }
}

resource "aws_lb_target_group_attachment" "gitlab_nlb" {
  target_group_arn = aws_lb_target_group.gitlab_ssh.arn
  target_id        = aws_instance.gitlab.id
}
